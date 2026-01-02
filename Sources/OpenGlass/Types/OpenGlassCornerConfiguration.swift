import Foundation

/// Configuration for all four corners of a glass element.
///
/// Supports two modes:
/// - **Corners**: Individual radius for each corner, either fixed or concentric.
/// - **Capsule**: Fully rounded ends (radius = half of shorter dimension).
///
/// **Example**:
/// ```swift
/// // Uniform fixed radius
/// .corners(radius: 16)
///
/// // Per-corner with concentric top
/// .corners(
///     topLeading: .containerConcentric(minimum: 8),
///     topTrailing: .containerConcentric(minimum: 8),
///     bottomLeading: 4,
///     bottomTrailing: 4
/// )
///
/// // Pill/capsule shape
/// .capsule()
/// ```
///
/// - SeeAlso: ``OpenGlassCornerRadius``, ``GlassCornerRadii``
public struct OpenGlassCornerConfiguration: Equatable, Hashable, Sendable {
    enum Storage: Equatable, Hashable, Sendable {
        case corners(
            topLeading: OpenGlassCornerRadius?,
            topTrailing: OpenGlassCornerRadius?,
            bottomLeading: OpenGlassCornerRadius?,
            bottomTrailing: OpenGlassCornerRadius?,
        )
        case capsule(maximumRadius: Double?)
    }

    let storage: Storage

    private init(storage: Storage) {
        self.storage = storage
    }

    /// Creates a configuration with uniform radius on all corners.
    ///
    /// - Parameter radius: Radius to apply to all four corners.
    /// - Returns: Configuration with uniform corners.
    public static func corners(radius: OpenGlassCornerRadius) -> OpenGlassCornerConfiguration {
        OpenGlassCornerConfiguration(storage: .corners(
            topLeading: radius,
            topTrailing: radius,
            bottomLeading: radius,
            bottomTrailing: radius,
        ))
    }

    /// Creates a capsule (pill) shape with fully rounded ends.
    ///
    /// The radius is set to half the shorter dimension, creating a true capsule.
    ///
    /// - Parameter maximumRadius: Optional cap on the radius.
    /// - Returns: Configuration for capsule shape.
    public static func capsule(maximumRadius: Double? = nil) -> OpenGlassCornerConfiguration {
        OpenGlassCornerConfiguration(storage: .capsule(maximumRadius: maximumRadius))
    }

    /// Creates a configuration with individual radius for each corner.
    ///
    /// - Parameters:
    ///   - topLeading: Top-left corner radius, or nil for default.
    ///   - topTrailing: Top-right corner radius, or nil for default.
    ///   - bottomLeading: Bottom-left corner radius, or nil for default.
    ///   - bottomTrailing: Bottom-right corner radius, or nil for default.
    /// - Returns: Configuration with per-corner radii.
    public static func corners(
        topLeading: OpenGlassCornerRadius?,
        topTrailing: OpenGlassCornerRadius?,
        bottomLeading: OpenGlassCornerRadius?,
        bottomTrailing: OpenGlassCornerRadius?,
    ) -> OpenGlassCornerConfiguration {
        OpenGlassCornerConfiguration(storage: .corners(
            topLeading: topLeading,
            topTrailing: topTrailing,
            bottomLeading: bottomLeading,
            bottomTrailing: bottomTrailing,
        ))
    }

    /// Resolves the configuration to concrete radius values.
    ///
    /// For capsule mode, calculates radius from size. For corner mode, resolves
    /// each corner's radius (handling concentric calculations if needed).
    ///
    /// - Parameters:
    ///   - size: Size of the glass element.
    ///   - containerRadius: Container's corner radius (for concentric calculations).
    ///   - inset: Distance from container edge (for concentric calculations).
    ///   - defaultRadius: Fallback radius for nil corners.
    /// - Returns: Resolved radii for all four corners.
    public func resolve(
        size: CGSize,
        containerRadius: CGFloat = 0,
        inset: CGFloat = 0,
        defaultRadius: CGFloat = 0,
    ) -> GlassCornerRadii {
        switch storage {
        case let .capsule(maximumRadius):
            var radius = min(size.width, size.height) / 2
            if let maximumRadius {
                radius = min(radius, CGFloat(maximumRadius))
            }
            return GlassCornerRadii(uniform: Float(radius))

        case let .corners(topLeading, topTrailing, bottomLeading, bottomTrailing):
            let resolveOne: (OpenGlassCornerRadius?) -> Float = { corner in
                guard let corner else { return Float(defaultRadius) }
                return Float(corner.resolve(containerRadius: containerRadius, inset: inset))
            }
            return GlassCornerRadii(
                topLeading: resolveOne(topLeading),
                topTrailing: resolveOne(topTrailing),
                bottomLeading: resolveOne(bottomLeading),
                bottomTrailing: resolveOne(bottomTrailing),
            )
        }
    }
}

extension OpenGlassCornerConfiguration: CustomStringConvertible {
    public var description: String {
        switch storage {
        case let .capsule(maximumRadius):
            if let maximumRadius {
                return "OpenGlassCornerConfiguration.capsule(maximumRadius: \(maximumRadius))"
            }
            return "OpenGlassCornerConfiguration.capsule()"

        case let .corners(topLeading, topTrailing, bottomLeading, bottomTrailing):
            if topLeading == topTrailing, topLeading == bottomLeading, topLeading == bottomTrailing {
                if let radius = topLeading {
                    return "OpenGlassCornerConfiguration.corners(radius: \(radius))"
                }
                return "OpenGlassCornerConfiguration.corners(radius: nil)"
            }
            return "OpenGlassCornerConfiguration.corners(topLeading: \(String(describing: topLeading)), topTrailing: \(String(describing: topTrailing)), bottomLeading: \(String(describing: bottomLeading)), bottomTrailing: \(String(describing: bottomTrailing)))"
        }
    }
}
