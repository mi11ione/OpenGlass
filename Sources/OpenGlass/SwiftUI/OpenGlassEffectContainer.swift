import SwiftUI

/// A container that enables liquid morphing effects between child glass views.
///
/// Wrap multiple `.openGlassEffect()` views in an `OpenGlassEffectContainer` to
/// enable smooth `smin()` SDF blending between them. Adjacent children flow into
/// each other like liquid mercury.
///
/// **Example**:
/// ```swift
/// OpenGlassEffectContainer(spacing: 12) {
///     HStack {
///         Text("One").padding().openGlassEffect()
///         Text("Two").padding().openGlassEffect()
///     }
/// }
/// ```
///
/// - Note: Children automatically detect they're in a container via environment.
/// - SeeAlso: ``GlassContainerCoordinator``
public struct OpenGlassEffectContainer<Content: View>: View {
    /// Blend zone width for morphing between children.
    let spacing: CGFloat
    let content: Content

    /// Creates a glass effect container.
    ///
    /// - Parameters:
    ///   - spacing: Blend zone width for liquid morphing. Default: 8.0.
    ///   - content: Child views to render with glass effects.
    public init(
        spacing: CGFloat = 8.0,
        @ViewBuilder content: () -> Content,
    ) {
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        OpenGlassContainerViewRepresentable(
            spacing: spacing,
            content: content,
        )
    }
}

extension OpenGlassEffectContainer: Sendable where Content: Sendable {}

/// UIViewRepresentable that bridges SwiftUI container to UIKit renderer.
struct OpenGlassContainerViewRepresentable<Content: View>: UIViewRepresentable {
    let spacing: CGFloat
    let content: Content

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> OpenGlassContainerWrapperView {
        let wrapper = OpenGlassContainerWrapperView()
        let glassCoordinator = context.coordinator.glassCoordinator

        let wrappedContent = OpenGlassContainerContentWrapper(
            content: content,
            spacing: spacing,
            coordinator: glassCoordinator,
        )

        let hosting = UIHostingController(rootView: wrappedContent)
        hosting.view.backgroundColor = .clear
        context.coordinator.hostingController = hosting

        wrapper.configure(
            spacing: spacing,
            coordinator: glassCoordinator,
            contentView: hosting.view,
        )

        return wrapper
    }

    func updateUIView(_ wrapper: OpenGlassContainerWrapperView, context: Context) {
        let glassCoordinator = context.coordinator.glassCoordinator

        let wrappedContent = OpenGlassContainerContentWrapper(
            content: content,
            spacing: spacing,
            coordinator: glassCoordinator,
        )

        context.coordinator.hostingController?.rootView = wrappedContent
        wrapper.updateSpacing(spacing)
        wrapper.setNeedsLayout()
    }

    @MainActor
    final class Coordinator {
        let glassCoordinator = GlassContainerCoordinator()
        var hostingController: UIHostingController<OpenGlassContainerContentWrapper<Content>>?
    }
}

/// Wrapper that injects container environment values into child content.
struct OpenGlassContainerContentWrapper<Content: View>: View {
    let content: Content
    let spacing: CGFloat
    let coordinator: GlassContainerCoordinator

    var body: some View {
        content
            .environment(\.openGlassContainerActive, true)
            .environment(\.openGlassContainerSpacing, spacing)
            .environment(\.openGlassContainerCoordinator, coordinator)
    }
}

/// UIView wrapper for the container, holding both the renderer and content.
final class OpenGlassContainerWrapperView: UIView {
    private var containerRenderView: OpenGlassContainerRenderView?
    private var contentView: UIView?
    private weak var coordinator: GlassContainerCoordinator?

    override var intrinsicContentSize: CGSize {
        contentView?.intrinsicContentSize ?? .zero
    }

    /// Configures the container with spacing, coordinator, and content.
    func configure(
        spacing: CGFloat,
        coordinator: GlassContainerCoordinator,
        contentView: UIView,
    ) {
        backgroundColor = .clear
        clipsToBounds = false
        self.coordinator = coordinator

        let renderView = OpenGlassContainerRenderView()
        renderView.spacing = spacing
        addSubview(renderView)
        containerRenderView = renderView

        coordinator.containerView = renderView
        renderView.coordinator = coordinator

        addSubview(contentView)
        self.contentView = contentView
    }

    func updateSpacing(_ spacing: CGFloat) {
        containerRenderView?.spacing = spacing
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        containerRenderView?.frame = bounds
        contentView?.frame = bounds

        DispatchQueue.main.async { [weak self] in
            self?.syncChildrenFrames()
        }
    }

    private func syncChildrenFrames() {
        guard let coordinator, let container = containerRenderView else { return }

        for reg in coordinator.getRegistrations() {
            guard let view = reg.view else { continue }
            let frameInContainer = view.convert(view.bounds, to: container)
            coordinator.updateFrame(id: reg.id, frame: frameInContainer)
        }
    }
}
