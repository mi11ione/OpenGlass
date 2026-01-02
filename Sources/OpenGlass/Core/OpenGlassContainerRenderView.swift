import MetalKit

/// A UIView that renders multiple glass children with liquid morphing effects.
///
/// `OpenGlassContainerRenderView` manages a collection of child glass elements and renders
/// them in a single Metal draw call. Adjacent children blend together using smooth minimum
/// SDF (`smin()`) functions, creating fluid mercury-like transitions.
///
/// For SwiftUI, use ``OpenGlassEffectContainer`` instead of this class directly.
///
/// **Example**:
/// ```swift
/// let container = OpenGlassContainerRenderView()
/// container.spacing = 12.0
/// container.glassStyle = .regular
/// parentView.addSubview(container)
///
/// container.registerChild(id: childId, view: childView, ...)
/// ```
///
/// - Note: Requires Metal-capable device. Maximum 64 children per container.
/// - SeeAlso: ``OpenGlassEffectContainer``, ``GlassContainerCoordinator``
public final class OpenGlassContainerRenderView: UIView {
    /// Controls the blend zone width for liquid morphing between children.
    ///
    /// Higher values create wider, smoother transitions. Default: 8.0 points.
    public var spacing: CGFloat = 8.0

    /// Visual style applied to all children in the container.
    ///
    /// - SeeAlso: ``OpenGlass/Style``
    public var glassStyle: OpenGlass.Style = .regular

    /// View to capture as background. Defaults to window's root view if nil.
    public weak var sourceView: UIView?

    /// Coordinator for managing child registrations from SwiftUI.
    public weak var coordinator: GlassContainerCoordinator?

    private var metalView: MTKView?
    private var renderer: OpenGlassContainerRenderer?
    private var childViews: [ObjectIdentifier: WeakChildRef] = [:]
    private var contentViews: [ObjectIdentifier: UIView] = [:]

    private static let maxStretch: CGFloat = 1.5
    private static let basePadding: CGFloat = 30.0

    private var stretchPadding: CGFloat {
        max(bounds.width, bounds.height) * (Self.maxStretch - 1.0) / 2.0 + Self.basePadding
    }

    private struct WeakChildRef {
        weak var view: UIView?
        var configuration: GlassChildConfiguration
    }

    override public init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }

        backgroundColor = .clear
        clipsToBounds = false
        isUserInteractionEnabled = true

        let mtkView = MTKView()
        mtkView.device = device
        mtkView.backgroundColor = .clear
        mtkView.isOpaque = false
        mtkView.framebufferOnly = false
        mtkView.isPaused = true
        mtkView.enableSetNeedsDisplay = true
        addSubview(mtkView)
        metalView = mtkView

        guard let containerRenderer = OpenGlassContainerRenderer(device: device, metalView: mtkView) else { return }
        renderer = containerRenderer
        mtkView.delegate = containerRenderer
    }

    override public func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            SharedGlassCapture.shared.registerContainer(self)
        } else {
            SharedGlassCapture.shared.unregisterContainer(self)
        }
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        metalView?.frame = bounds.insetBy(dx: -stretchPadding, dy: -stretchPadding)
    }

    /// Registers a child view for glass rendering.
    ///
    /// Preserves existing physics state (stretch, rotation, offset) when re-registering
    /// an existing child with updated visual parameters.
    ///
    /// - Parameters:
    ///   - id: Unique identifier for tracking this child.
    ///   - view: The UIView representing the child's frame.
    ///   - contentView: Content to hide during capture (prevents self-capture artifacts).
    ///   - cornerRadii: Per-corner radius values.
    ///   - tintColor: Optional custom tint color for this child.
    ///   - tintMode: Blend mode for tint color.
    ///   - tintIntensity: Tint blend intensity.
    public func registerChild(
        id: ObjectIdentifier,
        view: UIView,
        contentView: UIView?,
        cornerRadii: GlassCornerRadii,
        tintColor: GlassTintColor?,
        tintMode: OpenGlassTintMode,
        tintIntensity: Float,
    ) {
        let existingPhysics = childViews[id]?.configuration

        var config = GlassChildConfiguration(
            id: id,
            frame: view.frame,
            cornerRadii: cornerRadii,
            tintColor: tintColor,
            tintMode: tintMode,
            tintIntensity: tintIntensity,
        )

        if let existing = existingPhysics {
            config.stretchX = existing.stretchX
            config.stretchY = existing.stretchY
            config.rotation = existing.rotation
            config.physicsOffset = existing.physicsOffset
            config.scale = existing.scale
            config.opacity = existing.opacity
        }

        childViews[id] = WeakChildRef(view: view, configuration: config)
        if let contentView {
            contentViews[id] = contentView
        }
    }

    /// Removes a child from the container.
    ///
    /// - Parameter id: Identifier of the child to remove.
    public func unregisterChild(id: ObjectIdentifier) {
        childViews.removeValue(forKey: id)
        contentViews.removeValue(forKey: id)
    }

    /// Updates a child's frame in container coordinates.
    ///
    /// - Parameters:
    ///   - id: Identifier of the child to update.
    ///   - frame: New frame in container coordinates.
    public func updateChildFrame(id: ObjectIdentifier, frame: CGRect) {
        guard var ref = childViews[id] else { return }
        ref.configuration.frame = frame
        childViews[id] = ref
    }

    /// Updates a child's corner radii.
    ///
    /// - Parameters:
    ///   - id: Identifier of the child to update.
    ///   - cornerRadii: New per-corner radius values.
    public func updateChildCornerRadii(
        id: ObjectIdentifier,
        cornerRadii: GlassCornerRadii,
    ) {
        guard var ref = childViews[id] else { return }
        ref.configuration.cornerRadii = cornerRadii
        childViews[id] = ref
    }

    /// Updates a child's physics animation state.
    ///
    /// Called by the physics engine each frame with the current animated values.
    ///
    /// - Parameters:
    ///   - id: Identifier of the child to update.
    ///   - stretchX: Horizontal stretch factor.
    ///   - stretchY: Vertical stretch factor.
    ///   - rotation: Rotation angle in radians.
    ///   - physicsOffset: Translation offset from physics.
    ///   - scale: Scale factor from spring animation.
    ///   - opacity: Opacity from spring animation.
    public func updateChildPhysics(
        id: ObjectIdentifier,
        stretchX: Float,
        stretchY: Float,
        rotation: Float,
        physicsOffset: CGPoint,
        scale: Float,
        opacity: Float,
    ) {
        guard var ref = childViews[id] else { return }
        ref.configuration.stretchX = stretchX
        ref.configuration.stretchY = stretchY
        ref.configuration.rotation = rotation
        ref.configuration.physicsOffset = physicsOffset
        ref.configuration.scale = scale
        ref.configuration.opacity = opacity
        childViews[id] = ref
    }

    func getChildConfigurations() -> [GlassChildConfiguration] {
        cleanupDeadRefs()
        return childViews.values.map(\.configuration)
    }

    func getContentViewsToHide() -> [UIView] {
        cleanupDeadRefs()
        return Array(contentViews.values)
    }

    func getChildViews() -> [UIView] {
        cleanupDeadRefs()
        return childViews.values.compactMap(\.view)
    }

    private func cleanupDeadRefs() {
        let deadIds = childViews.filter { $0.value.view == nil }.map(\.key)
        for id in deadIds {
            childViews.removeValue(forKey: id)
            contentViews.removeValue(forKey: id)
        }
    }

    func renderWithSharedCapture(
        texture: MTLTexture,
        captureSize: CGSize,
        offset: CGPoint,
    ) {
        guard let renderer, let metalView, bounds.width > 0, bounds.height > 0 else { return }

        let configs = getChildConfigurations()
        guard !configs.isEmpty else { return }

        renderer.updateChildren(configs)

        let glassConfig = makeGlassConfiguration()

        renderer.updateUniforms(
            containerSize: bounds.size,
            renderSize: metalView.bounds.size,
            padding: stretchPadding,
            backgroundSize: captureSize,
            backgroundOffset: offset,
            spacing: spacing,
            blurRadius: glassConfig.blurRadius,
            refractionStrength: glassConfig.refractionStrength,
            chromeStrength: glassConfig.chromeStrength,
            edgeBandMultiplier: glassConfig.edgeBandMultiplier,
            glassTintStrength: glassConfig.glassTintStrength,
            zoom: glassConfig.zoom,
            topHighlightStrength: glassConfig.topHighlightStrength,
            edgeShadowStrength: glassConfig.edgeShadowStrength,
            overallShadowStrength: glassConfig.overallShadowStrength,
            isDarkMode: traitCollection.userInterfaceStyle == .dark,
            texture: texture,
        )

        metalView.draw()
    }

    private func makeGlassConfiguration() -> GlassConfiguration {
        var config = GlassConfiguration()
        config.applyStyle(glassStyle)
        return config
    }
}
