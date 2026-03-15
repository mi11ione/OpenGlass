import OGCapture

public struct GlassConfiguration {
    public var cornerRadius: Float = 32.0
    public var refractionStrength: Float = 1.0
    public var edgeBandMultiplier: Float = 0.1
    public var chromeStrength: Float = 0.0
    public var blurRadius: Float = 2.4
    public var zoom: Float = 1.0
    public var edgeShadowStrength: Float = 0.01
    public var overallShadowStrength: Float = 0.02
    public var glassTintStrength: Float = 0.85

    public enum PhysicsMode: Int, Sendable {
        case none = 0
        case press = 1
        case free = 2
        case anchored = 3
    }

    public var physicsMode: PhysicsMode = .none
    public var pressedScale: Float = 1.12
    public var pressedOpacity: Float = 1.0
    public var scaleStiffness: Float = 300.0
    public var scaleDamping: Float = 20.0
    public var opacityStiffness: Float = 400.0
    public var opacityDamping: Float = 25.0
    public var stretchStiffness: Float = 220.0
    public var stretchDamping: Float = 16.0
    public var rotationStiffness: Float = 200.0
    public var rotationDamping: Float = 14.0
    public var offsetStiffness: Float = 280.0
    public var offsetDamping: Float = 20.0
    public var velocityStretchSensitivity: Float = 0.0006
    public var maxStretch: Float = 1.12
    public var minStretch: Float = 0.92
    public var velocityRotationSensitivity: Float = 0.0
    public var maxRotation: Float = 0.0
    public var anchoredStretchSensitivity: Float = 0.0008
    public var anchoredMaxStretch: Float = 1.08
    public var anchoredMaxOffset: Float = 12.0
    public var anchoredOffsetStiffness: Float = 0.006

    public init() {}

    public mutating func applyStyle(_ style: OpenGlass.Style) {
        switch style {
        case .regular:
            blurRadius = 8.0
        case .clear:
            blurRadius = 2.5
            refractionStrength = 0.6
            chromeStrength = 0.0
            glassTintStrength = 0.10
        case .identity:
            refractionStrength = 0
            chromeStrength = 0
            blurRadius = 0
            edgeShadowStrength = 0
            overallShadowStrength = 0
            glassTintStrength = 0
        }
    }

    public static var regular: GlassConfiguration { GlassConfiguration() }

    public static var clear: GlassConfiguration {
        var c = GlassConfiguration()
        c.applyStyle(.clear)
        return c
    }

    public static var identity: GlassConfiguration {
        var c = GlassConfiguration()
        c.applyStyle(.identity)
        return c
    }

    var cConfig: OGGlassConfig {
        OGGlassConfig(
            cornerRadius: cornerRadius,
            refractionStrength: refractionStrength,
            edgeBandMultiplier: edgeBandMultiplier,
            chromeStrength: chromeStrength,
            blurRadius: blurRadius,
            zoom: zoom,
            edgeShadowStrength: edgeShadowStrength,
            overallShadowStrength: overallShadowStrength,
            glassTintStrength: glassTintStrength,
            physicsMode: OGPhysicsMode(rawValue: UInt8(physicsMode.rawValue)),
            pressedScale: pressedScale,
            pressedOpacity: pressedOpacity,
            scaleStiffness: scaleStiffness,
            scaleDamping: scaleDamping,
            opacityStiffness: opacityStiffness,
            opacityDamping: opacityDamping,
            stretchStiffness: stretchStiffness,
            stretchDamping: stretchDamping,
            rotationStiffness: rotationStiffness,
            rotationDamping: rotationDamping,
            offsetStiffness: offsetStiffness,
            offsetDamping: offsetDamping,
            velocityStretchSensitivity: velocityStretchSensitivity,
            maxStretch: maxStretch,
            minStretch: minStretch,
            velocityRotationSensitivity: velocityRotationSensitivity,
            maxRotation: maxRotation,
            anchoredStretchSensitivity: anchoredStretchSensitivity,
            anchoredMaxStretch: anchoredMaxStretch,
            anchoredMaxOffset: anchoredMaxOffset,
            anchoredOffsetStiffness: anchoredOffsetStiffness
        )
    }
}
