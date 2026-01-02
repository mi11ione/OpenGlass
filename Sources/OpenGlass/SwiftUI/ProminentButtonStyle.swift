import SwiftUI

/// A prominent button style with tinted glass effect.
///
/// Similar to ``OpenGlassButtonStyle`` but with accent color tinting,
/// bold text, and larger padding for primary actions.
///
/// **Example**:
/// ```swift
/// Button("Submit") { }
///     .buttonStyle(.openGlassProminent)
/// ```
///
/// - SeeAlso: ``OpenGlassButtonStyle``
public struct OpenGlassProminentButtonStyle: ButtonStyle {
    /// Creates a prominent glass button style.
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.bold())
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .openGlassEffect(OpenGlass.regular.tint(.accentColor).anchored())
    }
}

public extension ButtonStyle where Self == OpenGlassProminentButtonStyle {
    /// The prominent glass button style with accent color tinting.
    static var openGlassProminent: OpenGlassProminentButtonStyle {
        OpenGlassProminentButtonStyle()
    }
}
