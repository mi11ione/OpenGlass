import SwiftUI

/// A button style that applies the Liquid Glass effect.
///
/// Creates buttons with glass backgrounds featuring refraction, chromatic
/// aberration, and physics-based press animations. Uses anchored physics
/// mode for press-and-release feedback.
///
/// **Example**:
/// ```swift
/// Button("Tap Me") { }
///     .buttonStyle(.openGlass)
///
/// Button("Tinted") { }
///     .buttonStyle(.openGlass(.regular.tint(.blue)))
/// ```
///
/// - SeeAlso: ``OpenGlassProminentButtonStyle``, ``OpenGlass``
public struct OpenGlassButtonStyle: ButtonStyle {
    let glass: OpenGlass

    /// Creates a button style with the default regular glass.
    public init() {
        glass = .regular
    }

    /// Creates a button style with a custom glass configuration.
    ///
    /// - Parameter glass: Glass style and configuration.
    public init(_ glass: OpenGlass) {
        self.glass = glass
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .openGlassEffect(glass.anchored())
    }
}

public extension ButtonStyle where Self == OpenGlassButtonStyle {
    /// The default glass button style.
    static var openGlass: OpenGlassButtonStyle {
        OpenGlassButtonStyle()
    }

    /// A glass button style with custom configuration.
    static func openGlass(_ glass: OpenGlass) -> OpenGlassButtonStyle {
        OpenGlassButtonStyle(glass)
    }
}
