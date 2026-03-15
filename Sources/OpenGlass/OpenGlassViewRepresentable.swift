import SwiftUI
import OGCapture

struct GlassContentWrapper<C: View>: View {
    let content: C
    let brightBackground: Bool

    var body: some View {
        content
            .foregroundColor(brightBackground ? .black : .white)
            .animation(.easeInOut(duration: 0.25), value: brightBackground)
    }
}

struct OpenGlassWrapperRepresentable<Content: View>: UIViewRepresentable {
    let glass: OpenGlass
    let cornerRadius: CGFloat?
    let content: Content

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> OpenGlassWrapperView {
        let wrapper = OpenGlassWrapperView()
        let wrapped = GlassContentWrapper(content: AnyView(content), brightBackground: false)
        let hosting = UIHostingController(rootView: wrapped)
        hosting.view.backgroundColor = .clear
        context.coordinator.hostingController = hosting
        context.coordinator.latestContent = AnyView(content)
        wrapper.configure(glass: glass, cornerRadius: cornerRadius, contentView: hosting.view)
        wrapper.onRegimeChange = { [weak coordinator = context.coordinator] isBright in
            coordinator?.update(bright: isBright)
        }
        return wrapper
    }

    func updateUIView(_ wrapper: OpenGlassWrapperView, context: Context) {
        context.coordinator.latestContent = AnyView(content)
        context.coordinator.update(bright: wrapper.isBackgroundBright)
        wrapper.updateGlass(glass: glass, cornerRadius: cornerRadius)
        wrapper.invalidateIntrinsicContentSize()
    }

    @MainActor
    final class Coordinator {
        var hostingController: UIHostingController<GlassContentWrapper<AnyView>>?
        var latestContent: AnyView = AnyView(EmptyView())

        func update(bright: Bool) {
            hostingController?.rootView = GlassContentWrapper(
                content: latestContent, brightBackground: bright
            )
        }
    }
}

final class OpenGlassWrapperView: UIView {
    private var glassView: OpenGlassView?
    private var contentView: UIView?
    private var explicitCornerRadius: CGFloat?
    private var contentDirty = true
    private var lastContentSize: CGSize = .zero
    private var contentTexture: MTLTexture?

    private(set) var isBackgroundBright = false
    var onRegimeChange: ((Bool) -> Void)?

    private static let bitmapInfo: UInt32 =
        CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    private static let regimeThreshold: Float = 0.5

    override var intrinsicContentSize: CGSize {
        contentView?.intrinsicContentSize ?? .zero
    }

    func configure(glass: OpenGlass, cornerRadius: CGFloat?, contentView: UIView) {
        configure(glass: glass, configuration: nil, cornerRadius: cornerRadius, contentView: contentView)
    }

    func configure(configuration: GlassConfiguration, cornerRadius: CGFloat?, contentView: UIView) {
        configure(glass: nil, configuration: configuration, cornerRadius: cornerRadius, contentView: contentView)
    }

    private func configure(glass: OpenGlass?, configuration: GlassConfiguration? = nil, cornerRadius: CGFloat?, contentView: UIView) {
        backgroundColor = .clear
        clipsToBounds = false
        self.explicitCornerRadius = cornerRadius

        let config = configuration ?? glass!.makeConfiguration()
        let glassView = OpenGlassView(configuration: config)
        glassView.exclusionLayer = self.layer
        addSubview(glassView)
        self.glassView = glassView

        addSubview(contentView)
        self.contentView = contentView

        glassView.installGestures(on: self)

        glassView.onPhysicsTransform = { [weak self] scale, opacity, sx, sy, rot, ox, oy in
            guard let cv = self?.contentView, !cv.isHidden else { return }
            var t = CATransform3DIdentity
            t = CATransform3DTranslate(t, CGFloat(ox), CGFloat(oy), 0)
            t = CATransform3DRotate(t, CGFloat(rot), 0, 0, 1)
            t = CATransform3DScale(t, CGFloat(sx * scale), CGFloat(sy * scale), 1)
            cv.layer.transform = t
            cv.alpha = CGFloat(opacity)
        }

        glassView.onLuminanceChange = { [weak self] lum in
            self?.handleLuminanceUpdate(lum)
        }
    }

    func updateGlass(glass: OpenGlass, cornerRadius: CGFloat?) {
        self.explicitCornerRadius = cornerRadius
        glassView?.configuration = glass.makeConfiguration()
        contentDirty = true
        setNeedsLayout()
    }

    func updateConfiguration(_ configuration: GlassConfiguration, cornerRadius: CGFloat?) {
        self.explicitCornerRadius = cornerRadius
        glassView?.configuration = configuration
        contentDirty = true
        setNeedsLayout()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            contentDirty = true
            setNeedsLayout()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        glassView?.frame = bounds
        contentView?.frame = bounds

        let radius = explicitCornerRadius ?? min(bounds.width, bounds.height) / 2
        glassView?.configuration.cornerRadius = Float(radius)

        captureContentIfNeeded()
    }

    private func handleLuminanceUpdate(_ lum: Float) {
        let bright = lum >= Self.regimeThreshold

        guard bright != isBackgroundBright else { return }
        isBackgroundBright = bright

        onRegimeChange?(bright)

        contentView?.layoutIfNeeded()
        if contentTexture != nil {
            contentDirty = true
            captureContentIfNeeded()
        }
    }

    private func captureContentIfNeeded() {
        guard let cv = contentView,
              let device = OGGlassEngine.shared?.device,
              let glassView
        else { return }

        guard glassView.configuration.physicsMode != .none else {
            if cv.isHidden {
                cv.isHidden = false
                cv.layer.transform = CATransform3DIdentity
                cv.alpha = 1
                glassView.setContentTexture(nil)
                contentTexture = nil
            }
            return
        }

        let size = cv.bounds.size
        guard size.width > 0, size.height > 0 else { return }
        if !contentDirty && contentTexture != nil && lastContentSize == size { return }

        cv.isHidden = false
        cv.layer.transform = CATransform3DIdentity
        cv.alpha = 1
        cv.layoutIfNeeded()

        let scale = window?.screen.scale ?? UIScreen.main.scale
        let w = Int(ceil(size.width * scale))
        let h = Int(ceil(size.height * scale))
        let bpr = w * 4

        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: h * bpr)
        defer { buffer.deallocate() }
        memset(buffer, 0, h * bpr)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: buffer, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: bpr,
            space: colorSpace, bitmapInfo: Self.bitmapInfo
        ) else { return }

        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: scale, y: -scale)
        cv.layer.render(in: ctx)

        cv.isHidden = true

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        desc.usage = .shaderRead
        desc.storageMode = .shared

        guard let texture = device.makeTexture(descriptor: desc) else {
            cv.isHidden = false
            return
        }
        texture.replace(
            region: MTLRegionMake2D(0, 0, w, h),
            mipmapLevel: 0, withBytes: buffer, bytesPerRow: bpr)

        contentTexture = texture
        lastContentSize = size
        contentDirty = false

        glassView.setContentTexture(texture)
    }
}
