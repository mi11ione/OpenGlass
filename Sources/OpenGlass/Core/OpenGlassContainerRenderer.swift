import MetalKit

/// Configuration for a single child glass element within a container.
///
/// Contains all per-child parameters including frame, corner radii, physics state,
/// and tint settings. Converted to GPU-friendly format before rendering.
///
/// - SeeAlso: ``OpenGlassContainerRenderer``, ``GlassContainerCoordinator``
struct GlassChildConfiguration {
    /// Unique identifier for tracking this child across frames.
    var id: ObjectIdentifier
    /// Frame in container coordinates.
    var frame: CGRect
    /// Per-corner radius values.
    var cornerRadii: GlassCornerRadii
    /// Horizontal stretch from physics animation.
    var stretchX: Float
    /// Vertical stretch from physics animation.
    var stretchY: Float
    /// Rotation angle from physics animation.
    var rotation: Float
    /// Offset from physics animation.
    var physicsOffset: CGPoint
    /// Scale from spring animation.
    var scale: Float
    /// Opacity from spring animation.
    var opacity: Float
    /// Optional custom tint color.
    var tintColor: GlassTintColor?
    /// Blend mode for tint color.
    var tintMode: OpenGlassTintMode
    /// Tint blend intensity.
    var tintIntensity: Float

    init(
        id: ObjectIdentifier,
        frame: CGRect,
        cornerRadii: GlassCornerRadii = GlassCornerRadii(uniform: 32),
        stretchX: Float = 1.0,
        stretchY: Float = 1.0,
        rotation: Float = 0.0,
        physicsOffset: CGPoint = .zero,
        scale: Float = 1.0,
        opacity: Float = 1.0,
        tintColor: GlassTintColor? = nil,
        tintMode: OpenGlassTintMode = .overlay,
        tintIntensity: Float = 1.0,
    ) {
        self.id = id
        self.frame = frame
        self.cornerRadii = cornerRadii
        self.stretchX = stretchX
        self.stretchY = stretchY
        self.rotation = rotation
        self.physicsOffset = physicsOffset
        self.scale = scale
        self.opacity = opacity
        self.tintColor = tintColor
        self.tintMode = tintMode
        self.tintIntensity = tintIntensity
    }
}

/// Metal rendering pipeline for container-based glass with multiple children.
///
/// Renders multiple glass children in a single draw call using `smin()` SDF blending
/// to create smooth liquid-like morphing between adjacent elements. Supports up to
/// 64 children per container. Uses shaders from `ContainerShaders.metal`.
///
/// The renderer evaluates all child SDFs per-pixel, finding the smoothed minimum
/// distance and blending optical parameters (tint, refraction) based on each child's
/// contribution to the final surface.
///
/// - Note: Internal class. Use ``OpenGlassEffectContainer`` for public API.
/// - SeeAlso: ``OpenGlassContainerRenderView``, ``GlassChildConfiguration``
@MainActor
final class OpenGlassContainerRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipelineState: MTLRenderPipelineState?
    private var backgroundTexture: MTLTexture?
    private var uniforms = ContainerUniforms()
    private var childBuffer: MTLBuffer?
    private var childConfigs: [GlassChildConfiguration] = []

    private static let screenScale = Float(UIScreen.main.scale)
    /// Maximum number of children supported per container.
    private static let maxChildren = 64

    /// Shader uniform buffer structure matching `ContainerShaders.metal` layout.
    ///
    /// Contains container-wide parameters. Per-child data is in the child buffer.
    struct ContainerUniforms {
        var containerSize: SIMD2<Float> = .zero
        var renderSize: SIMD2<Float> = .zero
        var padding: Float = 0.0
        var _padding1: Float = 0.0
        var backgroundSize: SIMD2<Float> = .zero
        var backgroundOffset: SIMD2<Float> = .zero
        var blurRadius: Float = 6.0
        var refractionStrength: Float = 0.4
        var chromeStrength: Float = 3.0
        var edgeBandMultiplier: Float = 0.25
        var glassTintStrength: Float = 0.3
        var zoom: Float = 1.0
        var topHighlightStrength: Float = 0.04
        var edgeShadowStrength: Float = 0.05
        var overallShadowStrength: Float = 0.02
        var isDarkMode: Float = 0.0
        var spacing: Float = 0.0
        var childCount: Int32 = 0
        var _padding2: Int32 = 0
    }

    /// GPU-friendly representation of a child glass element.
    ///
    /// Packed for efficient buffer transfer. Must match Metal struct layout exactly.
    struct GlassChildGPU {
        var center: SIMD2<Float>
        var halfSize: SIMD2<Float>
        var cornerRadii: SIMD4<Float>
        var stretchX: Float
        var stretchY: Float
        var rotation: Float
        var physicsOffsetX: Float
        var physicsOffsetY: Float
        var scale: Float
        var opacity: Float
        var tintColorR: Float
        var tintColorG: Float
        var tintColorB: Float
        var hasTint: Float
        var tintMode: Float
        var tintIntensity: Float
    }

    /// Creates a container renderer with the specified Metal device and view.
    ///
    /// - Parameters:
    ///   - device: Metal device for GPU operations.
    ///   - metalView: MTKView to render into.
    /// - Returns: Configured renderer, or nil if pipeline setup fails.
    init?(device: MTLDevice, metalView: MTKView) {
        guard let commandQueue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.commandQueue = commandQueue
        super.init()
        setupPipeline(metalView: metalView)
        setupChildBuffer()
    }

    private func setupPipeline(metalView: MTKView) {
        guard let library = try? device.makeDefaultLibrary(bundle: Bundle.module),
              let vertexFunc = library.makeFunction(name: "containerVertexShader"),
              let fragmentFunc = library.makeFunction(name: "containerFragmentShader")
        else { return }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunc
        descriptor.fragmentFunction = fragmentFunc
        descriptor.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        pipelineState = try? device.makeRenderPipelineState(descriptor: descriptor)
    }

    private func setupChildBuffer() {
        let bufferSize = MemoryLayout<GlassChildGPU>.stride * Self.maxChildren
        childBuffer = device.makeBuffer(length: bufferSize, options: .storageModeShared)
    }

    /// Updates the list of child configurations for the next render.
    ///
    /// - Parameter children: Array of child configurations (max 64 will be rendered).
    func updateChildren(_ children: [GlassChildConfiguration]) {
        childConfigs = children
    }

    /// Updates container-wide uniforms and background texture.
    ///
    /// Call this before each render frame with the current container state.
    /// Also triggers child buffer update with screen-scaled values.
    func updateUniforms(
        containerSize: CGSize,
        renderSize: CGSize,
        padding: CGFloat,
        backgroundSize: CGSize,
        backgroundOffset: CGPoint,
        spacing: CGFloat,
        blurRadius: Float,
        refractionStrength: Float,
        chromeStrength: Float,
        edgeBandMultiplier: Float,
        glassTintStrength: Float,
        zoom: Float,
        topHighlightStrength: Float,
        edgeShadowStrength: Float,
        overallShadowStrength: Float,
        isDarkMode: Bool,
        texture: MTLTexture,
    ) {
        let scale = Self.screenScale

        uniforms.containerSize = SIMD2<Float>(Float(containerSize.width) * scale, Float(containerSize.height) * scale)
        uniforms.renderSize = SIMD2<Float>(Float(renderSize.width) * scale, Float(renderSize.height) * scale)
        uniforms.padding = Float(padding) * scale
        uniforms.backgroundSize = SIMD2<Float>(Float(backgroundSize.width) * scale, Float(backgroundSize.height) * scale)
        uniforms.backgroundOffset = SIMD2<Float>(Float(backgroundOffset.x) * scale, Float(backgroundOffset.y) * scale)
        uniforms.spacing = Float(spacing) * scale
        uniforms.blurRadius = blurRadius * scale
        uniforms.refractionStrength = refractionStrength
        uniforms.chromeStrength = chromeStrength
        uniforms.edgeBandMultiplier = edgeBandMultiplier
        uniforms.glassTintStrength = glassTintStrength
        uniforms.zoom = zoom
        uniforms.topHighlightStrength = topHighlightStrength
        uniforms.edgeShadowStrength = edgeShadowStrength
        uniforms.overallShadowStrength = overallShadowStrength
        uniforms.isDarkMode = isDarkMode ? 1.0 : 0.0
        uniforms.childCount = Int32(min(childConfigs.count, Self.maxChildren))

        backgroundTexture = texture

        updateChildBuffer(scale: scale)
    }

    private func updateChildBuffer(scale: Float) {
        guard let buffer = childBuffer else { return }

        let pointer = buffer.contents().bindMemory(to: GlassChildGPU.self, capacity: Self.maxChildren)

        for (index, child) in childConfigs.prefix(Self.maxChildren).enumerated() {
            let centerX = Float(child.frame.midX) * scale
            let centerY = Float(child.frame.midY) * scale
            let halfWidth = Float(child.frame.width) * 0.5 * scale
            let halfHeight = Float(child.frame.height) * 0.5 * scale

            let maxRadius = Float(min(child.frame.width, child.frame.height) / 2)
            let clampedRadii = child.cornerRadii.clamped(to: maxRadius).scaled(by: scale)

            let gpuChild = GlassChildGPU(
                center: SIMD2<Float>(centerX, centerY),
                halfSize: SIMD2<Float>(halfWidth, halfHeight),
                cornerRadii: clampedRadii.simd4,
                stretchX: child.stretchX,
                stretchY: child.stretchY,
                rotation: child.rotation,
                physicsOffsetX: Float(child.physicsOffset.x) * scale,
                physicsOffsetY: Float(child.physicsOffset.y) * scale,
                scale: child.scale,
                opacity: child.opacity,
                tintColorR: child.tintColor?.red ?? 1.0,
                tintColorG: child.tintColor?.green ?? 1.0,
                tintColorB: child.tintColor?.blue ?? 1.0,
                hasTint: child.tintColor != nil ? 1.0 : 0.0,
                tintMode: Float(child.tintMode.rawValue),
                tintIntensity: child.tintIntensity,
            )

            pointer[index] = gpuChild
        }
    }

    func mtkView(_: MTKView, drawableSizeWillChange _: CGSize) {}

    /// Executes the container glass render pass.
    ///
    /// Renders all children in a single draw call. The fragment shader evaluates
    /// each child's SDF per-pixel, computing `smin()` blends for smooth morphing.
    /// Skips rendering if no children are registered.
    func draw(in view: MTKView) {
        guard let pipelineState,
              let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let backgroundTexture,
              let childBuffer,
              uniforms.childCount > 0
        else { return }

        descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        descriptor.colorAttachments[0].loadAction = .clear

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
        else { return }

        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentTexture(backgroundTexture, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ContainerUniforms>.stride, index: 0)
        encoder.setFragmentBuffer(childBuffer, offset: 0, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
