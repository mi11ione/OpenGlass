/// Resolved corner radius values for all four corners.
///
/// Stores the final computed radius values in points (as `Float` for GPU compatibility).
/// This is the resolved form of ``OpenGlassCornerConfiguration`` ready for shader use.
///
/// **Example**:
/// ```swift
/// // Uniform radius
/// let uniform = GlassCornerRadii(uniform: 16)
///
/// // Per-corner
/// let perCorner = GlassCornerRadii(
///     topLeading: 20,
///     topTrailing: 20,
///     bottomLeading: 8,
///     bottomTrailing: 8
/// )
/// ```
///
/// - SeeAlso: ``OpenGlassCornerConfiguration``, ``GlassConfiguration/cornerRadii``
public struct GlassCornerRadii: Equatable, Sendable {
    /// Top-left corner radius in points.
    public var topLeading: Float
    /// Top-right corner radius in points.
    public var topTrailing: Float
    /// Bottom-left corner radius in points.
    public var bottomLeading: Float
    /// Bottom-right corner radius in points.
    public var bottomTrailing: Float

    /// Creates radii with individual values for each corner.
    ///
    /// - Parameters:
    ///   - topLeading: Top-left radius. Default: 0.
    ///   - topTrailing: Top-right radius. Default: 0.
    ///   - bottomLeading: Bottom-left radius. Default: 0.
    ///   - bottomTrailing: Bottom-right radius. Default: 0.
    public init(
        topLeading: Float = 0,
        topTrailing: Float = 0,
        bottomLeading: Float = 0,
        bottomTrailing: Float = 0,
    ) {
        self.topLeading = topLeading
        self.topTrailing = topTrailing
        self.bottomLeading = bottomLeading
        self.bottomTrailing = bottomTrailing
    }

    /// Creates radii with the same value for all corners.
    ///
    /// - Parameter radius: Radius to apply to all four corners.
    public init(uniform radius: Float) {
        topLeading = radius
        topTrailing = radius
        bottomLeading = radius
        bottomTrailing = radius
    }

    /// Creates radii from a SIMD4 vector.
    ///
    /// Component mapping: x=topLeading, y=topTrailing, z=bottomLeading, w=bottomTrailing.
    ///
    /// - Parameter simd: SIMD4 containing the four radius values.
    public init(_ simd: SIMD4<Float>) {
        topLeading = simd.x
        topTrailing = simd.y
        bottomLeading = simd.z
        bottomTrailing = simd.w
    }

    /// Converts to SIMD4 for shader uniform buffers.
    ///
    /// Component mapping: x=topLeading, y=topTrailing, z=bottomLeading, w=bottomTrailing.
    public var simd4: SIMD4<Float> {
        SIMD4(topLeading, topTrailing, bottomLeading, bottomTrailing)
    }

    /// Returns radii multiplied by a scale factor.
    ///
    /// Used for converting points to pixels (screen scale).
    ///
    /// - Parameter scale: Multiplier for all radius values.
    /// - Returns: Scaled radii.
    public func scaled(by scale: Float) -> GlassCornerRadii {
        GlassCornerRadii(
            topLeading: topLeading * scale,
            topTrailing: topTrailing * scale,
            bottomLeading: bottomLeading * scale,
            bottomTrailing: bottomTrailing * scale,
        )
    }

    /// Returns radii clamped to a maximum value.
    ///
    /// Prevents radii from exceeding half the element's shorter dimension.
    ///
    /// - Parameter maxRadius: Maximum allowed radius.
    /// - Returns: Clamped radii.
    public func clamped(to maxRadius: Float) -> GlassCornerRadii {
        GlassCornerRadii(
            topLeading: min(topLeading, maxRadius),
            topTrailing: min(topTrailing, maxRadius),
            bottomLeading: min(bottomLeading, maxRadius),
            bottomTrailing: min(bottomTrailing, maxRadius),
        )
    }
}
