import SwiftUI

/// Builder for configuring Liquid Glass effect parameters.
///
/// `OpenGlass` provides a fluent API for configuring glass appearance and physics behavior.
/// Start with a style (`.regular`, `.clear`, `.identity`) and chain modifiers to customize.
///
/// **Example**:
/// ```swift
/// OpenGlass.regular
///     .tint(.blue)
///     .anchored()
///
/// OpenGlass.clear
///     .tint(.purple, mode: .screen, intensity: 0.8)
///     .freeDrag()
/// ```
///
/// - SeeAlso: ``GlassConfiguration``, ``OpenGlassTintMode``, ``OpenGlassPhysicsBounds``
public struct OpenGlass: Equatable, Sendable {
    /// Visual style presets for the glass effect.
    ///
    /// Each style configures optical properties (blur, refraction, tint) for different use cases.
    public enum Style: Int, Sendable {
        /// Standard glass with moderate blur, refraction, and tinting. Default choice.
        case regular = 0
        /// Transparent glass with minimal blur and tint. Best for overlaying readable content.
        case clear = 1
        /// No visual effect. Useful for animating glass appearance from nothing.
        case identity = 2
    }

    let style: Style
    let tintColor: GlassTintColor?
    let tintMode: OpenGlassTintMode
    let tintIntensity: Float
    let targetScale: Float
    let targetOpacity: Float
    let physicsConfiguration: OpenGlassPhysicsConfiguration

    private init(
        style: Style,
        tintColor: GlassTintColor? = nil,
        tintMode: OpenGlassTintMode = .overlay,
        tintIntensity: Float = 1.0,
        targetScale: Float = 1.0,
        targetOpacity: Float = 1.0,
        physics: OpenGlassPhysicsConfiguration = OpenGlassPhysicsConfiguration(),
    ) {
        self.style = style
        self.tintColor = tintColor
        self.tintMode = tintMode
        self.tintIntensity = tintIntensity
        self.targetScale = targetScale
        self.targetOpacity = targetOpacity
        physicsConfiguration = physics
    }

    /// Standard glass with moderate blur, refraction, and tinting.
    public static var regular: OpenGlass {
        OpenGlass(style: .regular)
    }

    /// Transparent glass with minimal blur. Best for overlaying readable content.
    public static var clear: OpenGlass {
        OpenGlass(style: .clear)
    }

    /// No visual effect. Useful for animating glass appearance from nothing.
    public static var identity: OpenGlass {
        OpenGlass(style: .identity)
    }

    /// Applies a tint color using the current blend mode.
    ///
    /// - Parameter color: SwiftUI color to tint with, or nil to remove tint.
    /// - Returns: New configuration with tint applied.
    public func tint(_ color: Color?) -> OpenGlass {
        let glassTint = color.flatMap { GlassTintColor($0) }
        return OpenGlass(style: style, tintColor: glassTint, tintMode: tintMode, tintIntensity: tintIntensity, targetScale: targetScale, targetOpacity: targetOpacity, physics: physicsConfiguration)
    }

    /// Applies a tint color with custom blend mode and intensity.
    ///
    /// - Parameters:
    ///   - color: SwiftUI color to tint with, or nil to remove tint.
    ///   - mode: Blend mode for combining tint with background.
    ///   - intensity: Blend strength (0.0 to 1.0). Default: 1.0.
    /// - Returns: New configuration with tint applied.
    public func tint(_ color: Color?, mode: OpenGlassTintMode, intensity: Float = 1.0) -> OpenGlass {
        let glassTint = color.flatMap { GlassTintColor($0) }
        return OpenGlass(style: style, tintColor: glassTint, tintMode: mode, tintIntensity: intensity, targetScale: targetScale, targetOpacity: targetOpacity, physics: physicsConfiguration)
    }

    /// Applies a tint using a pre-created ``GlassTintColor``.
    ///
    /// - Parameter tint: Tint color, or nil to remove tint.
    /// - Returns: New configuration with tint applied.
    public func tint(_ tint: GlassTintColor?) -> OpenGlass {
        OpenGlass(style: style, tintColor: tint, tintMode: tintMode, tintIntensity: tintIntensity, targetScale: targetScale, targetOpacity: targetOpacity, physics: physicsConfiguration)
    }

    /// Sets the blend mode for tint color.
    ///
    /// - Parameter mode: Blend mode to use.
    /// - Returns: New configuration with blend mode set.
    /// - SeeAlso: ``OpenGlassTintMode``
    public func tintMode(_ mode: OpenGlassTintMode) -> OpenGlass {
        OpenGlass(style: style, tintColor: tintColor, tintMode: mode, tintIntensity: tintIntensity, targetScale: targetScale, targetOpacity: targetOpacity, physics: physicsConfiguration)
    }

    /// Sets the intensity of tint blending.
    ///
    /// - Parameter intensity: Blend strength (0.0 = no tint, 1.0 = full tint).
    /// - Returns: New configuration with intensity set.
    public func tintIntensity(_ intensity: Float) -> OpenGlass {
        OpenGlass(style: style, tintColor: tintColor, tintMode: tintMode, tintIntensity: intensity, targetScale: targetScale, targetOpacity: targetOpacity, physics: physicsConfiguration)
    }

    /// Sets the target scale for spring animation.
    ///
    /// The glass will animate toward this scale using spring physics.
    ///
    /// - Parameter scale: Target scale factor.
    /// - Returns: New configuration with scale set.
    public func scale(_ scale: Float) -> OpenGlass {
        OpenGlass(style: style, tintColor: tintColor, tintMode: tintMode, tintIntensity: tintIntensity, targetScale: scale, targetOpacity: targetOpacity, physics: physicsConfiguration)
    }

    /// Sets the target opacity for spring animation.
    ///
    /// The glass will animate toward this opacity using spring physics.
    ///
    /// - Parameter opacity: Target opacity (0.0 to 1.0).
    /// - Returns: New configuration with opacity set.
    public func opacity(_ opacity: Float) -> OpenGlass {
        OpenGlass(style: style, tintColor: tintColor, tintMode: tintMode, tintIntensity: tintIntensity, targetScale: targetScale, targetOpacity: opacity, physics: physicsConfiguration)
    }

    /// Applies a complete physics configuration.
    ///
    /// - Parameter config: Physics configuration to use.
    /// - Returns: New configuration with physics applied.
    /// - SeeAlso: ``OpenGlassPhysicsConfiguration``
    public func physics(_ config: OpenGlassPhysicsConfiguration) -> OpenGlass {
        OpenGlass(style: style, tintColor: tintColor, tintMode: tintMode, tintIntensity: tintIntensity, targetScale: targetScale, targetOpacity: targetOpacity, physics: config)
    }

    /// Sets the physics bounds mode.
    ///
    /// - Parameter bounds: Bounds constraint for physics interactions.
    /// - Returns: New configuration with bounds set.
    /// - SeeAlso: ``OpenGlassPhysicsBounds``
    public func physicsBounds(_ bounds: OpenGlassPhysicsBounds) -> OpenGlass {
        var config = physicsConfiguration
        config.bounds = bounds
        return OpenGlass(style: style, tintColor: tintColor, tintMode: tintMode, tintIntensity: tintIntensity, targetScale: targetScale, targetOpacity: targetOpacity, physics: config)
    }

    /// Enables free dragging with no position constraints.
    ///
    /// Equivalent to `.physicsBounds(.none)`.
    public func freeDrag() -> OpenGlass {
        physicsBounds(.none)
    }

    /// Anchors the glass to its original position with stretch feedback.
    ///
    /// The glass stretches when dragged but springs back to center on release.
    /// Equivalent to `.physicsBounds(.anchored)`.
    public func anchored() -> OpenGlass {
        physicsBounds(.anchored)
    }

    /// Constrains horizontal movement within bounds.
    ///
    /// - Parameters:
    ///   - min: Minimum X position.
    ///   - max: Maximum X position.
    /// - Returns: New configuration with horizontal bounds.
    public func horizontalBounds(min: CGFloat, max: CGFloat) -> OpenGlass {
        physicsBounds(.horizontal(min: min, max: max))
    }

    /// Constrains vertical movement within bounds.
    ///
    /// - Parameters:
    ///   - min: Minimum Y position.
    ///   - max: Maximum Y position.
    /// - Returns: New configuration with vertical bounds.
    public func verticalBounds(min: CGFloat, max: CGFloat) -> OpenGlass {
        physicsBounds(.vertical(min: min, max: max))
    }

    /// Constrains movement within a rectangle.
    ///
    /// - Parameter rect: Bounding rectangle for movement.
    /// - Returns: New configuration with rectangular bounds.
    public func bounded(_ rect: CGRect) -> OpenGlass {
        physicsBounds(.rect(rect))
    }

    /// Converts this builder to a full ``GlassConfiguration``.
    ///
    /// Used internally to create the configuration passed to renderers.
    ///
    /// - Returns: Complete configuration with all settings applied.
    public func makeConfiguration() -> GlassConfiguration {
        var config = GlassConfiguration()
        config.applyStyle(style)
        config.tintColor = tintColor
        config.tintMode = tintMode
        config.tintIntensity = tintIntensity
        config.targetScale = targetScale
        config.targetOpacity = targetOpacity
        config.physics = physicsConfiguration
        return config
    }
}
