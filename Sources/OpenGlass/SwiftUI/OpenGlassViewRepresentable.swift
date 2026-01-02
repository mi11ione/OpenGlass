import SwiftUI

/// UIViewRepresentable for standalone glass views (not in a container).
///
/// Wraps SwiftUI content in an ``OpenGlassWrapperView`` which contains both
/// the glass effect layer and the hosted content. Used by ``OpenGlassModifier``
/// when not inside an ``OpenGlassEffectContainer``.
///
/// - SeeAlso: ``OpenGlassModifier``, ``OpenGlassWrapperView``
struct OpenGlassWrapperRepresentable<Content: View>: UIViewRepresentable {
    let glass: OpenGlass
    let openCornerConfiguration: OpenGlassCornerConfiguration
    let content: Content

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> OpenGlassWrapperView {
        let wrapper = OpenGlassWrapperView()
        let hosting = UIHostingController(rootView: content)
        hosting.view.backgroundColor = .clear
        context.coordinator.hostingController = hosting
        wrapper.configure(glass: glass, openCornerConfiguration: openCornerConfiguration, contentView: hosting.view)
        return wrapper
    }

    func updateUIView(_ wrapper: OpenGlassWrapperView, context: Context) {
        context.coordinator.hostingController?.rootView = content
        wrapper.updateGlass(glass: glass, openCornerConfiguration: openCornerConfiguration)
        wrapper.invalidateIntrinsicContentSize()
    }

    final class Coordinator {
        var hostingController: UIHostingController<Content>?
    }
}

/// UIView container for standalone glass effects.
///
/// Contains an ``OpenGlassView`` for the glass effect and a content view
/// for the SwiftUI content. Manages layout sync and physics gesture handling.
final class OpenGlassWrapperView: UIView {
    private var glassView: OpenGlassView?
    private var contentView: UIView?
    private var openCornerConfiguration: OpenGlassCornerConfiguration = .capsule()
    private var physicsHandler: GlassPhysicsGestureHandler?

    override var intrinsicContentSize: CGSize {
        contentView?.intrinsicContentSize ?? .zero
    }

    /// Configures the wrapper with glass settings and content.
    func configure(glass: OpenGlass, openCornerConfiguration: OpenGlassCornerConfiguration, contentView: UIView) {
        backgroundColor = .clear
        clipsToBounds = false
        self.openCornerConfiguration = openCornerConfiguration

        let glassView = OpenGlassView(configuration: glass.anchored().makeConfiguration())
        glassView.physicsGestureEnabled = false
        glassView.clipsToBounds = false
        addSubview(glassView)
        self.glassView = glassView

        addSubview(contentView)
        self.contentView = contentView

        glassView.contentViewToHide = contentView

        physicsHandler = GlassPhysicsGestureHandler(attachTo: self, glassView: glassView)
    }

    func updateGlass(glass: OpenGlass, openCornerConfiguration: OpenGlassCornerConfiguration) {
        self.openCornerConfiguration = openCornerConfiguration
        glassView?.configuration = glass.anchored().makeConfiguration()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        glassView?.frame = bounds
        contentView?.frame = bounds

        glassView?.configuration.cornerRadii = openCornerConfiguration.resolve(size: bounds.size)
    }
}
