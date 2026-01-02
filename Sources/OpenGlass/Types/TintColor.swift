import SwiftUI

/// RGB color for glass tinting, stored as GPU-compatible floats.
///
/// Provides conversion from SwiftUI `Color`, UIKit `UIColor`, and SIMD3 vectors.
/// Alpha is not used since tint intensity is controlled separately via ``OpenGlass/tintIntensity(_:)``.
///
/// **Example**:
/// ```swift
/// // From RGB values
/// let custom = GlassTintColor(red: 0.2, green: 0.5, blue: 1.0)
///
/// // From SwiftUI Color
/// let blue = GlassTintColor(.blue)
///
/// // From UIColor
/// let systemPink = GlassTintColor(.systemPink)
/// ```
///
/// - SeeAlso: ``OpenGlass``, ``OpenGlassTintMode``
public struct GlassTintColor: Equatable, Sendable {
    /// Red component (0.0 to 1.0).
    public var red: Float
    /// Green component (0.0 to 1.0).
    public var green: Float
    /// Blue component (0.0 to 1.0).
    public var blue: Float

    /// Creates a tint color from RGB components.
    ///
    /// - Parameters:
    ///   - red: Red component (0.0 to 1.0).
    ///   - green: Green component (0.0 to 1.0).
    ///   - blue: Blue component (0.0 to 1.0).
    public init(red: Float, green: Float, blue: Float) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Creates a tint color from a SIMD3 vector.
    ///
    /// - Parameter simd: Vector with x=red, y=green, z=blue.
    public init(_ simd: SIMD3<Float>) {
        red = simd.x
        green = simd.y
        blue = simd.z
    }

    /// Creates a tint color from a UIColor.
    ///
    /// Extracts RGB components; alpha is ignored.
    ///
    /// - Parameter color: UIColor to convert.
    public init(_ color: UIColor) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        red = Float(r)
        green = Float(g)
        blue = Float(b)
    }

    /// Creates a tint color from a SwiftUI Color.
    ///
    /// Uses reflection to extract the underlying CGColor. Returns nil for colors
    /// that cannot be resolved (e.g., dynamic colors without a current trait collection).
    ///
    /// - Parameter color: SwiftUI Color to convert.
    public init?(_ color: Color) {
        guard let cgColor = color.cgColorValue else { return nil }
        self.init(UIColor(cgColor: cgColor))
    }

    /// Converts to SIMD3 for shader uniform buffers.
    public var simd3: SIMD3<Float> {
        SIMD3(red, green, blue)
    }

    /// Pure white tint color.
    public static let white = GlassTintColor(red: 1, green: 1, blue: 1)
}

private extension Color {
    var cgColorValue: CGColor? {
        let mirror = Mirror(reflecting: self)
        guard let provider = mirror.children.first?.value else { return resolveSystemColor() }
        let providerMirror = Mirror(reflecting: provider)
        for child in providerMirror.children {
            if String(describing: type(of: child.value)) == "CGColor" {
                return unsafeDowncast(child.value as AnyObject, to: CGColor.self)
            }
        }
        return resolveSystemColor()
    }

    private func resolveSystemColor() -> CGColor? {
        switch self {
        case .red: UIColor.systemRed.cgColor
        case .orange: UIColor.systemOrange.cgColor
        case .yellow: UIColor.systemYellow.cgColor
        case .green: UIColor.systemGreen.cgColor
        case .blue: UIColor.systemBlue.cgColor
        case .purple: UIColor.systemPurple.cgColor
        case .pink: UIColor.systemPink.cgColor
        case .gray: UIColor.systemGray.cgColor
        case .white: UIColor.white.cgColor
        case .black: UIColor.black.cgColor
        case .clear: UIColor.clear.cgColor
        case .primary: UIColor.label.cgColor
        case .secondary: UIColor.secondaryLabel.cgColor
        default: nil
        }
    }
}
