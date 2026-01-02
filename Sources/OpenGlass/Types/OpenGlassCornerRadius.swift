import Foundation

/// A corner radius value that can be fixed or calculated relative to a container.
///
/// Supports two modes:
/// - **Fixed**: An absolute radius in points.
/// - **Concentric**: Calculated as `containerRadius - inset`, maintaining visual alignment
///   with the container's corners (like nested rounded rectangles).
///
/// **Example**:
/// ```swift
/// // Fixed radius
/// let fixed: OpenGlassCornerRadius = 16.0
///
/// // Concentric with container
/// let concentric = OpenGlassCornerRadius.containerConcentric(minimum: 8)
/// ```
///
/// - Note: Conforms to `ExpressibleByFloatLiteral` and `ExpressibleByIntegerLiteral`
///   for convenient literal syntax.
/// - SeeAlso: ``OpenGlassCornerConfiguration``, ``GlassCornerRadii``
public struct OpenGlassCornerRadius: Equatable, Hashable, Sendable {
    enum Storage: Equatable, Hashable, Sendable {
        case fixed(Double)
        case concentric(minimum: CGFloat?)
    }

    let storage: Storage

    private init(storage: Storage) {
        self.storage = storage
    }

    /// Creates a fixed corner radius.
    ///
    /// - Parameter radius: Radius in points.
    /// - Returns: A fixed corner radius value.
    public static func fixed(_ radius: Double) -> OpenGlassCornerRadius {
        OpenGlassCornerRadius(storage: .fixed(radius))
    }

    /// Creates a radius that adjusts based on container radius and inset.
    ///
    /// The radius is calculated as `max(0, containerRadius - inset)`, which maintains
    /// visual concentricity with the container's corners.
    ///
    /// - Parameter minimum: Optional minimum radius to ensure visibility.
    /// - Returns: A concentric corner radius value.
    public static func containerConcentric(minimum: CGFloat? = nil) -> OpenGlassCornerRadius {
        OpenGlassCornerRadius(storage: .concentric(minimum: minimum))
    }

    /// Resolves the actual radius value given container parameters.
    ///
    /// - Parameters:
    ///   - containerRadius: The container's corner radius.
    ///   - inset: Distance from container edge to this element.
    /// - Returns: The resolved radius in points.
    public func resolve(containerRadius: CGFloat, inset: CGFloat) -> CGFloat {
        switch storage {
        case let .fixed(radius):
            return CGFloat(radius)
        case let .concentric(minimum):
            let calculated = max(0, containerRadius - inset)
            if let minimum {
                return max(calculated, minimum)
            }
            return calculated
        }
    }
}

extension OpenGlassCornerRadius: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        storage = .fixed(value)
    }
}

extension OpenGlassCornerRadius: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        storage = .fixed(Double(value))
    }
}

extension OpenGlassCornerRadius: CustomStringConvertible {
    public var description: String {
        switch storage {
        case let .fixed(radius):
            return "OpenGlassCornerRadius.fixed(\(radius))"
        case let .concentric(minimum):
            if let minimum {
                return "OpenGlassCornerRadius.containerConcentric(minimum: \(minimum))"
            }
            return "OpenGlassCornerRadius.containerConcentric()"
        }
    }
}
