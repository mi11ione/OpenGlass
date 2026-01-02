import MetalKit

/// Metal rendering pipeline for standalone glass views.
///
/// Manages the GPU pipeline state, uniform buffer, and draw commands for rendering
/// the Liquid Glass effect. Uses fragment shaders from `Shaders.metal` to apply
/// SDF-based shape masking, refraction, chromatic aberration, and blur.
///
/// - Note: Internal class. Use ``OpenGlassView`` for public API.
/// - SeeAlso: ``OpenGlassView``, ``OpenGlassContainerRenderer``
@MainActor
final class OpenGlassRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipelineState: MTLRenderPipelineState?
    private var backgroundTexture: MTLTexture?
    private var uniforms = Uniforms()

    private static let screenScale = Float(UIScreen.main.scale)

    /// Shader uniform buffer structure matching `Shaders.metal` layout.
    ///
    /// All size values are in pixels (pre-scaled by screen scale).
    /// Must match the Metal shader struct exactly for correct memory layout.
    struct Uniforms {
        var size: SIMD2<Float> = .zero
        var renderSize: SIMD2<Float> = .zero
        var padding: Float = 0
        var offset: SIMD2<Float> = .zero
        var backgroundSize: SIMD2<Float> = .zero
        var cornerRadii: SIMD4<Float> = .zero
        var blurRadius: Float = 0
        var refractionStrength: Float = 0
        var chromeStrength: Float = 0
        var edgeBandMultiplier: Float = 0
        var glassTintStrength: Float = 0
        var zoom: Float = 1
        var topHighlightStrength: Float = 0
        var edgeShadowStrength: Float = 0
        var overallShadowStrength: Float = 0
        var isDarkMode: Float = 0
        var tintColor: SIMD3<Float> = .init(1, 1, 1)
        var hasTintColor: Float = 0
        var tintMode: Float = 1
        var tintIntensity: Float = 1
        var scale: Float = 1
        var opacity: Float = 1
        var stretchX: Float = 1
        var stretchY: Float = 1
        var rotation: Float = 0
        var physicsOffsetX: Float = 0
        var physicsOffsetY: Float = 0
    }

    /// Creates a renderer with the specified Metal device and view.
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
    }

    private func setupPipeline(metalView: MTKView) {
        guard let library = try? device.makeDefaultLibrary(bundle: Bundle.module),
              let vertexFunc = library.makeFunction(name: "vertexShader"),
              let fragmentFunc = library.makeFunction(name: "fragmentShader")
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

    /// Updates shader uniforms and background texture for the next draw call.
    ///
    /// Converts all point-based values to pixels using screen scale. Called by
    /// ``OpenGlassView`` before each render frame with current configuration
    /// and animation state.
    ///
    /// - Parameters:
    ///   - size: Logical size of the glass view in points.
    ///   - renderSize: Size of the Metal drawable including padding.
    ///   - padding: Extra padding around the view for stretch effects.
    ///   - offset: Position offset within the captured background texture.
    ///   - backgroundSize: Size of the captured background region.
    ///   - cornerRadii: Per-corner radius values.
    ///   - blurRadius: Background blur radius in points.
    ///   - refractionStrength: Edge refraction intensity.
    ///   - chromeStrength: Chromatic aberration intensity.
    ///   - edgeBandMultiplier: Edge effect zone width.
    ///   - glassTintStrength: Base tint blend strength.
    ///   - zoom: Center magnification factor.
    ///   - topHighlightStrength: Top edge highlight intensity.
    ///   - edgeShadowStrength: Edge darkening intensity.
    ///   - overallShadowStrength: Global shadow intensity.
    ///   - isDarkMode: Whether dark mode appearance is active.
    ///   - tintColor: Optional custom tint color.
    ///   - tintMode: Blend mode for tint color.
    ///   - tintIntensity: Tint blend intensity.
    ///   - scale: Current animated scale.
    ///   - opacity: Current animated opacity.
    ///   - stretchX: Horizontal stretch factor from physics.
    ///   - stretchY: Vertical stretch factor from physics.
    ///   - rotation: Rotation angle from physics.
    ///   - physicsOffsetX: Horizontal offset from physics.
    ///   - physicsOffsetY: Vertical offset from physics.
    ///   - texture: Background texture to sample from.
    func updateUniforms(
        size: CGSize,
        renderSize: CGSize,
        padding: CGFloat,
        offset: CGPoint,
        backgroundSize: CGSize,
        cornerRadii: GlassCornerRadii,
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
        tintColor: GlassTintColor?,
        tintMode: OpenGlassTintMode,
        tintIntensity: Float,
        scale: Float,
        opacity: Float,
        stretchX: Float,
        stretchY: Float,
        rotation: Float,
        physicsOffsetX: Float,
        physicsOffsetY: Float,
        texture: MTLTexture,
    ) {
        let screenScale = Self.screenScale

        uniforms.size = SIMD2<Float>(Float(size.width) * screenScale, Float(size.height) * screenScale)
        uniforms.renderSize = SIMD2<Float>(Float(renderSize.width) * screenScale, Float(renderSize.height) * screenScale)
        uniforms.padding = Float(padding) * screenScale
        uniforms.offset = SIMD2<Float>(Float(offset.x) * screenScale, Float(offset.y) * screenScale)
        uniforms.backgroundSize = SIMD2<Float>(Float(backgroundSize.width) * screenScale, Float(backgroundSize.height) * screenScale)
        uniforms.cornerRadii = cornerRadii.scaled(by: screenScale).simd4
        uniforms.blurRadius = blurRadius * screenScale
        uniforms.refractionStrength = refractionStrength
        uniforms.chromeStrength = chromeStrength
        uniforms.edgeBandMultiplier = edgeBandMultiplier
        uniforms.glassTintStrength = glassTintStrength
        uniforms.zoom = zoom
        uniforms.topHighlightStrength = topHighlightStrength
        uniforms.edgeShadowStrength = edgeShadowStrength
        uniforms.overallShadowStrength = overallShadowStrength
        uniforms.isDarkMode = isDarkMode ? 1.0 : 0.0

        if let tintColor {
            uniforms.tintColor = tintColor.simd3
            uniforms.hasTintColor = 1.0
        } else {
            uniforms.tintColor = SIMD3<Float>(1, 1, 1)
            uniforms.hasTintColor = 0.0
        }
        uniforms.tintMode = Float(tintMode.rawValue)
        uniforms.tintIntensity = tintIntensity

        uniforms.scale = scale
        uniforms.opacity = opacity
        uniforms.stretchX = stretchX
        uniforms.stretchY = stretchY
        uniforms.rotation = rotation
        uniforms.physicsOffsetX = physicsOffsetX * screenScale
        uniforms.physicsOffsetY = physicsOffsetY * screenScale

        backgroundTexture = texture
    }

    func mtkView(_: MTKView, drawableSizeWillChange _: CGSize) {}

    /// Executes the glass effect render pass.
    ///
    /// Draws a full-screen quad with the glass fragment shader, sampling from
    /// the background texture and applying all optical effects. Uses alpha blending
    /// for smooth edges via SDF-based anti-aliasing.
    func draw(in view: MTKView) {
        guard let pipelineState,
              let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let backgroundTexture else { return }

        descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        descriptor.colorAttachments[0].loadAction = .clear

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }

        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentTexture(backgroundTexture, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
