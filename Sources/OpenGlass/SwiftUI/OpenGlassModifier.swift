import SwiftUI

/// View modifier that applies the Liquid Glass effect to SwiftUI views.
///
/// Automatically detects whether the view is inside an ``OpenGlassEffectContainer``
/// (via environment) and uses the appropriate rendering path:
/// - **Inside container**: Registers as a container child for morphing effects
/// - **Standalone**: Creates an independent glass view
///
/// Applied via the `.openGlassEffect()` view extension.
///
/// - SeeAlso: ``OpenGlassEffectContainer``, ``OpenGlassWrapperRepresentable``
struct OpenGlassModifier: ViewModifier {
    let glass: OpenGlass
    let cornerConfiguration: OpenGlassCornerConfiguration

    @Environment(\.openGlassContainerActive) private var isInContainer
    @Environment(\.openGlassContainerCoordinator) private var coordinator

    func body(content: Content) -> some View {
        if isInContainer, let coordinator {
            OpenGlassContainerChildRepresentable(
                glass: glass,
                openCornerConfiguration: cornerConfiguration,
                coordinator: coordinator,
                content: content,
            )
            .fixedSize()
        } else {
            OpenGlassWrapperRepresentable(
                glass: glass,
                openCornerConfiguration: cornerConfiguration,
                content: content,
            )
            .fixedSize()
        }
    }
}

private func extractCornerConfiguration(from shape: some Shape) -> OpenGlassCornerConfiguration {
    if shape is Capsule || shape is Circle {
        return .capsule()
    }

    let mirror = Mirror(reflecting: shape)
    for child in mirror.children {
        if child.label == "cornerSize" {
            let sizeMirror = Mirror(reflecting: child.value)
            for sizeChild in sizeMirror.children {
                if sizeChild.label == "width" || sizeChild.label == "height" {
                    if let value = sizeChild.value as? CGFloat {
                        return .corners(radius: .fixed(Double(value)))
                    }
                }
            }
        }
        if child.label == "cornerRadius", let value = child.value as? CGFloat {
            return .corners(radius: .fixed(Double(value)))
        }
    }

    return .corners(radius: .fixed(16))
}

/// UIViewRepresentable for glass elements inside a container.
///
/// Creates an ``OpenGlassContainerChildView`` and registers it with the container
/// coordinator for morphing effects.
struct OpenGlassContainerChildRepresentable<Content: View>: UIViewRepresentable {
    let glass: OpenGlass
    let openCornerConfiguration: OpenGlassCornerConfiguration
    let coordinator: GlassContainerCoordinator
    let content: Content

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> OpenGlassContainerChildView {
        let childView = OpenGlassContainerChildView()
        let hosting = UIHostingController(rootView: content)
        hosting.view.backgroundColor = .clear
        context.coordinator.hostingController = hosting

        childView.configure(
            glass: glass,
            openCornerConfiguration: openCornerConfiguration,
            coordinator: coordinator,
            contentView: hosting.view,
        )

        return childView
    }

    func updateUIView(_ childView: OpenGlassContainerChildView, context: Context) {
        context.coordinator.hostingController?.rootView = content
        childView.updateGlass(glass: glass, openCornerConfiguration: openCornerConfiguration)
        childView.invalidateIntrinsicContentSize()
    }

    final class Coordinator {
        var hostingController: UIHostingController<Content>?
    }
}

/// UIView wrapper for a container child element.
///
/// Hosts SwiftUI content and manages registration with the container coordinator.
/// Handles lifecycle (register on appear, unregister on disappear) and layout sync.
final class OpenGlassContainerChildView: UIView {
    private var contentView: UIView?
    private weak var coordinator: GlassContainerCoordinator?
    private var glass: OpenGlass = .regular
    private var openCornerConfiguration: OpenGlassCornerConfiguration = .capsule()
    private var isRegistered = false
    private var physicsHandler: GlassPhysicsGestureHandler?

    override var intrinsicContentSize: CGSize {
        contentView?.intrinsicContentSize ?? .zero
    }

    /// Configures the child view with its glass settings and content.
    func configure(
        glass: OpenGlass,
        openCornerConfiguration: OpenGlassCornerConfiguration,
        coordinator: GlassContainerCoordinator,
        contentView: UIView,
    ) {
        backgroundColor = .clear
        self.glass = glass
        self.openCornerConfiguration = openCornerConfiguration
        self.coordinator = coordinator

        addSubview(contentView)
        self.contentView = contentView

        physicsHandler = GlassPhysicsGestureHandler(attachTo: self, childId: ObjectIdentifier(self))
    }

    func updateGlass(glass: OpenGlass, openCornerConfiguration: OpenGlassCornerConfiguration) {
        self.glass = glass
        self.openCornerConfiguration = openCornerConfiguration

        if isRegistered {
            coordinator?.updateCornerRadii(id: ObjectIdentifier(self), openCornerConfiguration: openCornerConfiguration)
            coordinator?.updateGlass(id: ObjectIdentifier(self), glass: glass)
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()

        if window != nil, !isRegistered {
            coordinator?.register(
                id: ObjectIdentifier(self),
                view: self,
                contentView: contentView,
                glass: glass,
                openCornerConfiguration: openCornerConfiguration,
            )
            isRegistered = true
        } else if window == nil, isRegistered {
            coordinator?.unregister(id: ObjectIdentifier(self))
            isRegistered = false
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        contentView?.frame = bounds

        if isRegistered {
            coordinator?.updateFrame(id: ObjectIdentifier(self), frame: frame)
        }
    }
}

/// SwiftUI Shape with per-corner radius support.
///
/// Used internally to create clip paths matching glass corner configurations.
struct PerCornerShape: Shape {
    let configuration: OpenGlassCornerConfiguration

    /// Creates a rounded rectangle path with independent corner radii.
    func path(in rect: CGRect) -> Path {
        let maxRadius = Float(min(rect.width, rect.height) / 2)
        let resolved = configuration.resolve(size: rect.size).clamped(to: maxRadius)
        return Path { path in
            let tl = CGFloat(resolved.topLeading)
            let tt = CGFloat(resolved.topTrailing)
            let bl = CGFloat(resolved.bottomLeading)
            let bt = CGFloat(resolved.bottomTrailing)

            path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - tt, y: rect.minY))
            path.addArc(
                center: CGPoint(x: rect.maxX - tt, y: rect.minY + tt),
                radius: tt,
                startAngle: .degrees(-90),
                endAngle: .degrees(0),
                clockwise: false,
            )
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bt))
            path.addArc(
                center: CGPoint(x: rect.maxX - bt, y: rect.maxY - bt),
                radius: bt,
                startAngle: .degrees(0),
                endAngle: .degrees(90),
                clockwise: false,
            )
            path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
            path.addArc(
                center: CGPoint(x: rect.minX + bl, y: rect.maxY - bl),
                radius: bl,
                startAngle: .degrees(90),
                endAngle: .degrees(180),
                clockwise: false,
            )
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
            path.addArc(
                center: CGPoint(x: rect.minX + tl, y: rect.minY + tl),
                radius: tl,
                startAngle: .degrees(180),
                endAngle: .degrees(270),
                clockwise: false,
            )
            path.closeSubpath()
        }
    }
}

public extension View {
    /// Applies a Liquid Glass effect to the view.
    ///
    /// Wraps the view in a glass layer with refraction, chromatic aberration,
    /// blur, and tinting effects. The corner radius is extracted from the shape.
    ///
    /// **Example**:
    /// ```swift
    /// Text("Hello")
    ///     .padding()
    ///     .openGlassEffect(.regular.tint(.blue), in: Capsule())
    /// ```
    ///
    /// - Parameters:
    ///   - glass: Glass style and configuration. Default: `.regular`.
    ///   - shape: Shape to extract corner radius from. Default: `Capsule()`.
    /// - Returns: View with glass effect applied.
    /// - SeeAlso: ``OpenGlass``, ``OpenGlassEffectContainer``
    func openGlassEffect(
        _ glass: OpenGlass = .regular,
        in shape: some Shape = Capsule(),
    ) -> some View {
        modifier(OpenGlassModifier(glass: glass, cornerConfiguration: extractCornerConfiguration(from: shape)))
    }

    /// Applies a Liquid Glass effect with explicit corner configuration.
    ///
    /// Use this overload when you need per-corner radius control or special
    /// radius modes (fixed, relative, minimum).
    ///
    /// **Example**:
    /// ```swift
    /// Text("Card")
    ///     .padding()
    ///     .openGlassEffect(
    ///         .regular,
    ///         openCornerConfiguration: .corners(radius: .fixed(24))
    ///     )
    /// ```
    ///
    /// - Parameters:
    ///   - glass: Glass style and configuration.
    ///   - openCornerConfiguration: Explicit corner radius configuration.
    /// - Returns: View with glass effect applied.
    func openGlassEffect(
        _ glass: OpenGlass = .regular,
        openCornerConfiguration: OpenGlassCornerConfiguration,
    ) -> some View {
        modifier(OpenGlassModifier(glass: glass, cornerConfiguration: openCornerConfiguration))
    }
}
