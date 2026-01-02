import MetalKit

/// A UIView that renders the Liquid Glass effect using Metal.
///
/// `OpenGlassView` captures the content behind it and applies real-time optical effects
/// including refraction, chromatic aberration, blur, and tinting via GPU shaders.
///
/// For SwiftUI, use the `.openGlassEffect()` modifier instead of this class directly.
///
/// **Example**:
/// ```swift
/// let glassView = OpenGlassView(configuration: .preset(.pill))
/// glassView.frame = CGRect(x: 100, y: 200, width: 200, height: 50)
/// parentView.addSubview(glassView)
/// ```
///
/// - Note: Requires Metal-capable device. Falls back gracefully on unsupported devices.
/// - SeeAlso: ``GlassConfiguration``
public final class OpenGlassView: UIView {
    /// Configuration controlling all visual and physics parameters.
    ///
    /// Changes take effect on the next render frame.
    public var configuration: GlassConfiguration

    /// View to capture as background. Defaults to window's root view if nil.
    public weak var sourceView: UIView?

    /// Content view to hide during capture to prevent self-capture artifacts.
    ///
    /// Set this to the view containing content displayed on top of the glass.
    public weak var contentViewToHide: UIView?

    /// Whether touch gestures trigger physics animations.
    ///
    /// When enabled, the view responds to touches with squash-stretch and rotation effects
    /// based on ``configuration``'s physics settings.
    public var physicsGestureEnabled: Bool = true {
        didSet {
            physicsHandler?.isEnabled = physicsGestureEnabled
        }
    }

    /// Current position for draggable glass views.
    ///
    /// Used by physics handler to track drag state. Update this to move the view programmatically.
    public var currentPosition: CGPoint = .zero

    /// Callback invoked when the view's position changes during drag.
    ///
    /// Use this to sync external state with the glass view's position.
    public var onPositionChange: ((CGPoint) -> Void)?

    private var metalView: MTKView?
    private var renderer: OpenGlassRenderer?
    private var physicsHandler: GlassPhysicsGestureHandler?

    private static let maxStretch: CGFloat = 1.5
    private static let basePadding: CGFloat = 30.0

    private var stretchPadding: CGFloat {
        max(bounds.width, bounds.height) * (Self.maxStretch - 1.0) / 2.0 + Self.basePadding
    }

    /// Creates a glass view with the specified configuration.
    ///
    /// - Parameter configuration: Visual and physics settings for the glass effect.
    public init(configuration: GlassConfiguration = GlassConfiguration()) {
        self.configuration = configuration
        super.init(frame: .zero)
        setup()
    }

    /// Creates a glass view with the specified frame and default configuration.
    override public init(frame: CGRect) {
        configuration = GlassConfiguration()
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        configuration = GlassConfiguration()
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }

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

        guard let glassRenderer = OpenGlassRenderer(device: device, metalView: mtkView) else { return }
        renderer = glassRenderer
        mtkView.delegate = glassRenderer

        physicsHandler = GlassPhysicsGestureHandler(attachTo: self, glassView: self)
    }

    override public func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            SharedGlassCapture.shared.register(self)
        } else {
            SharedGlassCapture.shared.unregister(self)
        }
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        metalView?.frame = bounds.insetBy(dx: -stretchPadding, dy: -stretchPadding)
    }

    func renderWithSharedCapture(
        texture: MTLTexture,
        captureSize: CGSize,
        offset: CGPoint,
        animatedScale: Float = 1.0,
        animatedOpacity: Float = 1.0,
        animatedStretchX: Float = 1.0,
        animatedStretchY: Float = 1.0,
        animatedRotation: Float = 0.0,
        animatedOffsetX: Float = 0.0,
        animatedOffsetY: Float = 0.0,
    ) {
        guard let renderer, bounds.width > 0, bounds.height > 0 else { return }

        let maxRadius = Float(min(bounds.width, bounds.height) / 2)
        let clampedRadii = configuration.cornerRadii.clamped(to: maxRadius)

        renderer.updateUniforms(
            size: bounds.size,
            renderSize: metalView?.bounds.size ?? bounds.size,
            padding: stretchPadding,
            offset: offset,
            backgroundSize: captureSize,
            cornerRadii: clampedRadii,
            blurRadius: configuration.blurRadius,
            refractionStrength: configuration.refractionStrength,
            chromeStrength: configuration.chromeStrength,
            edgeBandMultiplier: configuration.edgeBandMultiplier,
            glassTintStrength: configuration.glassTintStrength,
            zoom: configuration.zoom,
            topHighlightStrength: configuration.topHighlightStrength,
            edgeShadowStrength: configuration.edgeShadowStrength,
            overallShadowStrength: configuration.overallShadowStrength,
            isDarkMode: traitCollection.userInterfaceStyle == .dark,
            tintColor: configuration.tintColor,
            tintMode: configuration.tintMode,
            tintIntensity: configuration.tintIntensity,
            scale: animatedScale,
            opacity: animatedOpacity,
            stretchX: animatedStretchX,
            stretchY: animatedStretchY,
            rotation: animatedRotation,
            physicsOffsetX: animatedOffsetX,
            physicsOffsetY: animatedOffsetY,
            texture: texture,
        )

        metalView?.draw()
    }
}
