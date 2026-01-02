/// Blend modes for applying tint color to the glass effect.
///
/// Each mode produces a different visual result when combining the tint color
/// with the background. The GPU shader implements these using standard blend equations.
///
/// **Example**:
/// ```swift
/// OpenGlass.regular.tint(.blue, mode: .screen, intensity: 0.7)
/// ```
///
/// - SeeAlso: ``OpenGlass/tint(_:mode:intensity:)``, ``GlassTintColor``
public enum OpenGlassTintMode: Int, Sendable, CaseIterable {
    /// Darkens by multiplying base × tint. Good for shadows and depth.
    case multiply = 0
    /// Combines multiply and screen based on base luminance. Balanced, default choice.
    case overlay = 1
    /// Lightens by inverting, multiplying, and inverting. Good for glows.
    case screen = 2
    /// Brightens by dividing base by inverted tint. Creates strong highlights.
    case colorDodge = 3
    /// Subtle blend similar to overlay but gentler. Good for natural lighting.
    case softLight = 4
}

extension OpenGlassTintMode: CustomStringConvertible {
    public var description: String {
        switch self {
        case .multiply: "Multiply"
        case .overlay: "Overlay"
        case .screen: "Screen"
        case .colorDodge: "Color Dodge"
        case .softLight: "Soft Light"
        }
    }
}
