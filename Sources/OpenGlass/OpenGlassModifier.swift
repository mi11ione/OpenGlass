import SwiftUI

struct OpenGlassModifier: ViewModifier {
    let glass: OpenGlass
    let cornerRadius: CGFloat?

    func body(content: Content) -> some View {
        OpenGlassWrapperRepresentable(
            glass: glass,
            cornerRadius: cornerRadius,
            content: content
        )
        .fixedSize()
    }
}

struct OpenGlassConfigModifier: ViewModifier {
    let configuration: GlassConfiguration
    let cornerRadius: CGFloat?

    func body(content: Content) -> some View {
        OpenGlassConfigWrapperRepresentable(
            configuration: configuration,
            cornerRadius: cornerRadius,
            content: content
        )
        .fixedSize()
    }
}

private struct OpenGlassConfigWrapperRepresentable<Content: View>: UIViewRepresentable {
    let configuration: GlassConfiguration
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
        wrapper.configure(configuration: configuration, cornerRadius: cornerRadius, contentView: hosting.view)
        wrapper.onRegimeChange = { [weak coordinator = context.coordinator] isBright in
            coordinator?.update(bright: isBright)
        }
        return wrapper
    }

    func updateUIView(_ wrapper: OpenGlassWrapperView, context: Context) {
        context.coordinator.latestContent = AnyView(content)
        context.coordinator.update(bright: wrapper.isBackgroundBright)
        wrapper.updateConfiguration(configuration, cornerRadius: cornerRadius)
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

public extension View {
    func openGlassEffect(_ glass: OpenGlass = .regular) -> some View {
        modifier(OpenGlassModifier(glass: glass, cornerRadius: nil))
    }

    func openGlassEffect(_ glass: OpenGlass = .regular, in shape: Capsule) -> some View {
        modifier(OpenGlassModifier(glass: glass, cornerRadius: nil))
    }

    func openGlassEffect(_ glass: OpenGlass = .regular, in shape: Circle) -> some View {
        modifier(OpenGlassModifier(glass: glass, cornerRadius: nil))
    }

    func openGlassEffect(_ glass: OpenGlass = .regular, in shape: Rectangle) -> some View {
        modifier(OpenGlassModifier(glass: glass, cornerRadius: .zero))
    }

    func openGlassEffect(_ glass: OpenGlass = .regular, in shape: RoundedRectangle) -> some View {
        modifier(OpenGlassModifier(glass: glass, cornerRadius: shape.cornerSize.width))
    }

    func openGlassEffect(_ glass: OpenGlass = .regular, cornerRadius: CGFloat) -> some View {
        modifier(OpenGlassModifier(glass: glass, cornerRadius: cornerRadius))
    }

    func openGlassEffect(configuration: GlassConfiguration) -> some View {
        modifier(OpenGlassConfigModifier(configuration: configuration, cornerRadius: nil))
    }

    func openGlassEffect(configuration: GlassConfiguration, cornerRadius: CGFloat) -> some View {
        modifier(OpenGlassConfigModifier(configuration: configuration, cornerRadius: cornerRadius))
    }
}
