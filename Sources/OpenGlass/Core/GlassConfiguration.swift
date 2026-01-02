import Foundation

/// Complete configuration for glass effect rendering and physics behavior.
///
/// Controls all visual parameters of the Liquid Glass effect including optical properties
/// (refraction, chromatic aberration), blur, tinting, highlights, shadows, and spring-based
/// physics animations. Use presets for common configurations or customize individual properties.
///
/// **Example**:
/// ```swift
/// var config = GlassConfiguration()
/// config.refractionStrength = 0.5
/// config.chromeStrength = 4.0
/// config.tintColor = GlassTintColor(red: 0.2, green: 0.4, blue: 1.0)
/// ```
///
/// - SeeAlso: ``OpenGlass``, ``OpenGlassView``, ``Preset``
public struct GlassConfiguration {
    /// Per-corner radius values for the glass shape.
    ///
    /// Allows different radii for each corner. Use ``cornerRadius`` for uniform radius.
    public var cornerRadii: GlassCornerRadii = .init(uniform: 32.0)

    /// Uniform corner radius applied to all corners.
    ///
    /// Convenience accessor that reads from `topLeading` and writes to all corners.
    public var cornerRadius: Float {
        get { cornerRadii.topLeading }
        set { cornerRadii = GlassCornerRadii(uniform: newValue) }
    }

    /// Intensity of edge lens distortion that bends light toward the center.
    ///
    /// Higher values create stronger refraction at edges, mimicking curved glass optics.
    /// Range: 0.0 (none) to 1.0+ (extreme). Default: 0.4.
    public var refractionStrength: Float = 0.4

    /// Width of the edge effect zone as a multiplier of the glass size.
    ///
    /// Controls how far from the edge optical effects extend inward.
    /// Range: 0.0 to 1.0. Default: 0.25 (25% of size).
    public var edgeBandMultiplier: Float = 0.25

    /// Intensity of chromatic aberration (RGB channel separation) at edges.
    ///
    /// Simulates how real glass disperses light into wavelengths. Red shifts outward,
    /// blue shifts inward. Higher values create more visible rainbow fringing.
    /// Range: 0.0 (none) to 10.0+ (extreme). Default: 3.0.
    public var chromeStrength: Float = 3.0

    /// Radius of background blur in points.
    ///
    /// Uses golden spiral sampling with 32 samples for GPU-efficient blur.
    /// Range: 0.0 (sharp) to 20.0+ (heavy blur). Default: 6.0.
    public var blurRadius: Float = 6.0

    /// Strength of the base glass tint overlay.
    ///
    /// Mixes background with base tint color (white in light mode, dark gray in dark mode).
    /// Range: 0.0 (transparent) to 1.0 (opaque tint). Default: 0.3.
    public var glassTintStrength: Float = 0.3

    /// Center magnification factor.
    ///
    /// Values above 1.0 create a lens magnification effect at the center.
    /// Range: 0.5 to 2.0. Default: 1.0 (no magnification).
    public var zoom: Float = 1.0

    /// Intensity of the highlight along the top edge.
    ///
    /// Simulates light reflection on the upper surface of glass.
    /// Range: 0.0 to 0.2. Default: 0.04.
    public var topHighlightStrength: Float = 0.04

    /// Intensity of darkening along the glass edges.
    ///
    /// Creates depth by darkening the perimeter.
    /// Range: 0.0 to 0.2. Default: 0.05.
    public var edgeShadowStrength: Float = 0.05

    /// Global darkening applied to the entire glass surface.
    ///
    /// Subtle uniform shadow for depth.
    /// Range: 0.0 to 0.1. Default: 0.02.
    public var overallShadowStrength: Float = 0.02

    /// Optional custom tint color applied on top of the base tint.
    ///
    /// When set, blended with the base using ``tintMode`` and ``tintIntensity``.
    public var tintColor: GlassTintColor?

    /// Blend mode for applying ``tintColor`` to the glass.
    ///
    /// - SeeAlso: ``OpenGlassTintMode``
    public var tintMode: OpenGlassTintMode = .overlay

    /// Strength of the custom tint color blend.
    ///
    /// Range: 0.0 (no effect) to 1.0 (full blend). Default: 1.0.
    public var tintIntensity: Float = 1.0

    /// Target scale for spring animation.
    ///
    /// The glass animates toward this scale using spring physics.
    /// Default: 1.0 (no scaling).
    public var targetScale: Float = 1.0

    /// Target opacity for spring animation.
    ///
    /// The glass animates toward this opacity using spring physics.
    /// Range: 0.0 to 1.0. Default: 1.0.
    public var targetOpacity: Float = 1.0

    /// Spring stiffness for scale animations (higher = faster response).
    public var scaleSpringStiffness: Float = 300.0

    /// Spring damping for scale animations (higher = less oscillation).
    public var scaleSpringDamping: Float = 20.0

    /// Spring stiffness for opacity animations.
    public var opacitySpringStiffness: Float = 400.0

    /// Spring damping for opacity animations.
    public var opacitySpringDamping: Float = 25.0

    /// Physics configuration for touch interactions and motion effects.
    ///
    /// - SeeAlso: ``OpenGlassPhysicsConfiguration``
    public var physics: OpenGlassPhysicsConfiguration = .init()

    /// Creates a configuration with default values.
    public init() {}

    /// Applies a predefined style to this configuration.
    ///
    /// Modifies optical and visual properties based on the style. Does not affect
    /// corner radii, tint color, or physics settings.
    ///
    /// - Parameter style: The style to apply (`.regular`, `.clear`, or `.identity`).
    /// - SeeAlso: ``OpenGlass/Style``
    public mutating func applyStyle(_ style: OpenGlass.Style) {
        switch style {
        case .regular:
            break

        case .clear:
            glassTintStrength = 0.03
            blurRadius = 2.0
            refractionStrength = 0.3
            chromeStrength = 2.0

        case .identity:
            refractionStrength = 0
            chromeStrength = 0
            blurRadius = 0
            glassTintStrength = 0
            topHighlightStrength = 0
            edgeShadowStrength = 0
            overallShadowStrength = 0
        }
    }

    /// Creates a configuration tuned for a specific use case.
    ///
    /// Each preset provides optimized optical properties, corner radii, and physics
    /// parameters for common glass element types. Use ``presetSize(_:)`` to get the
    /// recommended dimensions for each preset.
    ///
    /// **Example**:
    /// ```swift
    /// let orbConfig = GlassConfiguration.preset(.orb)
    /// let orbSize = GlassConfiguration.presetSize(.orb)
    /// ```
    ///
    /// - Parameter preset: The preset type to use.
    /// - Returns: A fully configured `GlassConfiguration` for the preset.
    /// - SeeAlso: ``Preset``, ``presetSize(_:)``
    public static func preset(_ preset: Preset) -> GlassConfiguration {
        var config = GlassConfiguration()
        switch preset {
        case .pill:
            config.cornerRadius = 100
            config.refractionStrength = 0.3
            config.chromeStrength = 2.0
            config.blurRadius = 1.0
            config.glassTintStrength = 0.0
            config.zoom = 1.0
            config.topHighlightStrength = 0.04
            config.edgeShadowStrength = 0.03
            config.overallShadowStrength = 0.02
            config.physics.velocityStretchSensitivity = 0.002
            config.physics.maxStretchAlongVelocity = 1.15
            config.physics.stretchSpringStiffness = 280
            config.physics.stretchSpringDamping = 18
            config.physics.pressedScale = 0.95
        case .card:
            config.cornerRadius = 24
            config.refractionStrength = 0.35
            config.chromeStrength = 2.5
            config.blurRadius = 4.0
            config.glassTintStrength = 0.05
            config.zoom = 1.0
            config.topHighlightStrength = 0.05
            config.edgeShadowStrength = 0.05
            config.overallShadowStrength = 0.03
            config.physics.velocityStretchSensitivity = 0.001
            config.physics.maxStretchAlongVelocity = 1.08
            config.physics.stretchSpringStiffness = 180
            config.physics.stretchSpringDamping = 15
            config.physics.velocityRotationSensitivity = 0.00005
            config.physics.maxRotation = 0.15
        case .orb:
            config.cornerRadius = 60
            config.refractionStrength = 0.55
            config.chromeStrength = 5.0
            config.blurRadius = 2.0
            config.glassTintStrength = 0.0
            config.zoom = 1.1
            config.topHighlightStrength = 0.07
            config.edgeShadowStrength = 0.06
            config.overallShadowStrength = 0.02
            config.physics.velocityStretchSensitivity = 0.0025
            config.physics.maxStretchAlongVelocity = 1.25
            config.physics.minStretchPerpendicular = 0.8
            config.physics.stretchSpringStiffness = 120
            config.physics.stretchSpringDamping = 10
            config.physics.velocityRotationSensitivity = 0.0001
            config.physics.maxRotation = 0.25
        case .panel:
            config.cornerRadius = 32
            config.refractionStrength = 0.15
            config.chromeStrength = 1.0
            config.blurRadius = 12.0
            config.glassTintStrength = 0.12
            config.zoom = 1.0
            config.topHighlightStrength = 0.03
            config.edgeShadowStrength = 0.04
            config.overallShadowStrength = 0.02
            config.physics.bounds = .anchored
            config.physics.anchoredStretchSensitivity = 0.006
            config.physics.anchoredMaxStretch = 1.25
            config.physics.anchoredMaxOffset = 20
            config.physics.pressedScale = 0.98
            config.physics.pressedOpacity = 0.9
        case .lens:
            config.cornerRadius = 100
            config.refractionStrength = 0.6
            config.chromeStrength = 4.5
            config.blurRadius = 0.0
            config.glassTintStrength = 0.0
            config.zoom = 1.06
            config.topHighlightStrength = 0.08
            config.edgeShadowStrength = 0.07
            config.overallShadowStrength = 0.01
            config.physics.velocityStretchSensitivity = 0.0018
            config.physics.maxStretchAlongVelocity = 1.2
            config.physics.stretchSpringStiffness = 350
            config.physics.stretchSpringDamping = 12
            config.physics.velocityRotationSensitivity = 0.00008
            config.physics.maxRotation = 0.2
        }
        return config
    }

    /// Returns the recommended size for a preset.
    ///
    /// These sizes are tuned to showcase each preset's optical properties at their best.
    /// Adjust as needed for your layout.
    ///
    /// - Parameter preset: The preset to get dimensions for.
    /// - Returns: Recommended width and height in points.
    /// - SeeAlso: ``preset(_:)``
    public static func presetSize(_ preset: Preset) -> CGSize {
        switch preset {
        case .pill: CGSize(width: 260, height: 56)
        case .card: CGSize(width: 300, height: 200)
        case .orb: CGSize(width: 160, height: 160)
        case .panel: CGSize(width: 320, height: 140)
        case .lens: CGSize(width: 180, height: 180)
        }
    }

    /// Predefined configurations for common glass element types.
    ///
    /// Each preset combines visual and physics parameters optimized for a specific use case:
    /// - ``pill``: Capsule-shaped buttons and tags with subtle effects.
    /// - ``card``: Content cards with moderate blur and refraction.
    /// - ``orb``: Circular elements with strong optical distortion.
    /// - ``panel``: Large anchored panels with heavy blur.
    /// - ``lens``: Magnifying glass effect with maximum refraction.
    ///
    /// - SeeAlso: ``preset(_:)``, ``presetSize(_:)``
    public enum Preset: CaseIterable {
        /// Capsule-shaped button with subtle refraction and responsive physics.
        case pill
        /// Content card with moderate blur and gentle motion effects.
        case card
        /// Circular element with strong optical distortion and bouncy physics.
        case orb
        /// Large anchored panel with heavy blur and stretch-on-drag behavior.
        case panel
        /// Magnifying lens with maximum refraction and no blur.
        case lens
    }
}
