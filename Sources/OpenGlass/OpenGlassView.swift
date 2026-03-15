import UIKit
import OGCapture

public final class OpenGlassView: UIView {
    public var configuration = GlassConfiguration() {
        didSet {
            OGGlassEngine.shared?.setConfig(configuration.cConfig, for: self)
            setNeedsLayout()
        }
    }

    public weak var sourceView: UIView? {
        didSet { OGGlassEngine.shared?.setSourceView(sourceView, for: self) }
    }

    weak var exclusionLayer: CALayer? {
        didSet { OGGlassEngine.shared?.setExclusionLayer(exclusionLayer, for: self) }
    }

    var onPhysicsTransform: ((Float, Float, Float, Float, Float, Float, Float) -> Void)?
    var onLuminanceChange: ((Float) -> Void)?
    private(set) var gesturesInstalled = false

    func setContentTexture(_ texture: MTLTexture?) {
        OGGlassEngine.shared?.setContentTexture(texture, for: self)
    }

    private var metalLayer: CAMetalLayer?

    private static let maxStretch: CGFloat = 1.5
    private static let basePadding: CGFloat = 30.0

    private var stretchPadding: CGFloat {
        guard configuration.physicsMode != .none else { return 0 }
        return max(bounds.width, bounds.height) * (Self.maxStretch - 1.0) / 2.0 + Self.basePadding
    }

    public convenience init(configuration: GlassConfiguration) {
        self.init(frame: .zero)
        self.configuration = configuration
    }

    override public init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        Self.bootstrapEngine()
        guard let engine = OGGlassEngine.shared else { return }

        isOpaque = false
        backgroundColor = .clear
        clipsToBounds = false

        let ml = CAMetalLayer()
        ml.device = engine.device
        ml.pixelFormat = .bgra8Unorm
        ml.isOpaque = false
        ml.framebufferOnly = true
        ml.presentsWithTransaction = true
        ml.contentsScale = UIScreen.main.scale
        layer.addSublayer(ml)
        metalLayer = ml
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        let pad = stretchPadding
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        metalLayer?.frame = bounds.insetBy(dx: -pad, dy: -pad)
        CATransaction.commit()
        updateShadow()
    }

    private func updateShadow() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let maxR = min(bounds.width, bounds.height) / 2
        let r = CGFloat(min(configuration.cornerRadius, Float(maxR)))
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 6)
        layer.shadowRadius = 12
        layer.shadowOpacity = 0.06
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: r).cgPath
    }

    override public func didMoveToWindow() {
        super.didMoveToWindow()
        guard let engine = OGGlassEngine.shared else { return }
        if let window {
            metalLayer?.contentsScale = window.screen.scale
            engine.register(self)
            if let ml = metalLayer { engine.setMetalLayer(ml, for: self) }
            engine.setConfig(configuration.cConfig, for: self)
            engine.setSourceView(sourceView, for: self)
            engine.setExclusionLayer(exclusionLayer, for: self)
            engine.setPhysicsTransform({ [weak self] scale, opacity, sx, sy, rot, ox, oy in
                self?.onPhysicsTransform?(scale, opacity, sx, sy, rot, ox, oy)
            }, for: self)
            engine.setLuminanceBlock({ [weak self] lum in
                self?.onLuminanceChange?(lum)
            }, for: self)
            if !gesturesInstalled && configuration.physicsMode != .none {
                installGestures(on: self)
            }
        } else {
            engine.unregisterView(self)
        }
    }

    func installGestures(on target: UIView) {
        guard !gesturesInstalled else { return }
        gesturesInstalled = true
        let press = UILongPressGestureRecognizer(target: self, action: #selector(handlePress(_:)))
        press.minimumPressDuration = 0
        press.cancelsTouchesInView = false
        press.delaysTouchesBegan = false
        press.delegate = self
        target.addGestureRecognizer(press)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 1
        pan.cancelsTouchesInView = false
        pan.delaysTouchesBegan = false
        pan.delegate = self
        target.addGestureRecognizer(pan)
    }

    @objc private func handlePress(_ gesture: UILongPressGestureRecognizer) {
        guard configuration.physicsMode != .none,
              let engine = OGGlassEngine.shared else { return }
        let loc = gesture.location(in: self)
        let rel = CGPoint(x: loc.x - bounds.midX, y: loc.y - bounds.midY)
        switch gesture.state {
        case .began:
            engine.setTouchActive(true, for: self, position: rel)
        case .ended, .cancelled, .failed:
            engine.setTouchActive(false, for: self, position: rel)
        default: break
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard configuration.physicsMode != .none,
              let engine = OGGlassEngine.shared else { return }
        let loc = gesture.location(in: self)
        let rel = CGPoint(x: loc.x - bounds.midX, y: loc.y - bounds.midY)
        let vel = gesture.velocity(in: superview)
        switch gesture.state {
        case .began, .changed:
            engine.setDragVelocity(vel, for: self)
            engine.setTouchActive(true, for: self, position: rel)
        case .ended, .cancelled, .failed:
            engine.setDragVelocity(.zero, for: self)
            engine.setTouchActive(false, for: self, position: rel)
        default: break
        }
    }

    private static var didBootstrap = false

    private static func bootstrapEngine() {
        guard !didBootstrap else { return }
        didBootstrap = true

        guard let device = MTLCreateSystemDefaultDevice(),
              let library = try? device.makeDefaultLibrary(bundle: Bundle.module)
        else { return }

        guard let vert = library.makeFunction(name: "vertexShader"),
              let frag = library.makeFunction(name: "fragmentShader")
        else { return }
        let gd = MTLRenderPipelineDescriptor()
        gd.vertexFunction = vert
        gd.fragmentFunction = frag
        gd.colorAttachments[0].pixelFormat = .bgra8Unorm
        gd.colorAttachments[0].isBlendingEnabled = true
        gd.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        gd.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        gd.colorAttachments[0].sourceAlphaBlendFactor = .one
        gd.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        guard let glassPipeline = try? device.makeRenderPipelineState(descriptor: gd) else { return }

        guard let cv = library.makeFunction(name: "compositorVertexShader"),
              let cf = library.makeFunction(name: "compositorFragmentShader")
        else { return }
        let cd = MTLRenderPipelineDescriptor()
        cd.vertexFunction = cv
        cd.fragmentFunction = cf
        cd.colorAttachments[0].pixelFormat = .bgra8Unorm
        cd.colorAttachments[0].isBlendingEnabled = true
        cd.colorAttachments[0].sourceRGBBlendFactor = .one
        cd.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        cd.colorAttachments[0].sourceAlphaBlendFactor = .one
        cd.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        guard let compPipeline = try? device.makeRenderPipelineState(descriptor: cd) else { return }

        guard let mbv = library.makeFunction(name: "maskBlitVertexShader"),
              let mbf = library.makeFunction(name: "maskBlitFragmentShader")
        else { return }
        let md = MTLRenderPipelineDescriptor()
        md.vertexFunction = mbv
        md.fragmentFunction = mbf
        md.colorAttachments[0].pixelFormat = .bgra8Unorm
        md.colorAttachments[0].isBlendingEnabled = true
        md.colorAttachments[0].sourceRGBBlendFactor = .one
        md.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        md.colorAttachments[0].sourceAlphaBlendFactor = .one
        md.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        guard let maskPipeline = try? device.makeRenderPipelineState(descriptor: md) else { return }

        guard let lumFunc = library.makeFunction(name: "averageLuminance"),
              let lumPipeline = try? device.makeComputePipelineState(function: lumFunc)
        else { return }

        OGGlassEngine.setup(with: device, glassPipeline: glassPipeline, compositorPipeline: compPipeline, maskApplyPipeline: maskPipeline, lumComputePipeline: lumPipeline)
    }
}

extension OpenGlassView: UIGestureRecognizerDelegate {
    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool { true }
}
