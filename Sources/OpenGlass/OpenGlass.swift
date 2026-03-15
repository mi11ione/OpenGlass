public struct OpenGlass: Equatable, Sendable {
    public enum Style: Int, Sendable {
        case regular = 0
        case clear = 1
        case identity = 2
    }

    let style: Style
    let physics: GlassConfiguration.PhysicsMode

    private init(style: Style, physics: GlassConfiguration.PhysicsMode = .none) {
        self.style = style
        self.physics = physics
    }

    public static var regular: OpenGlass { OpenGlass(style: .regular) }
    public static var clear: OpenGlass { OpenGlass(style: .clear) }
    public static var identity: OpenGlass { OpenGlass(style: .identity) }

    public func press() -> OpenGlass {
        OpenGlass(style: style, physics: .press)
    }

    public func anchored() -> OpenGlass {
        OpenGlass(style: style, physics: .anchored)
    }

    public func free() -> OpenGlass {
        OpenGlass(style: style, physics: .free)
    }

    public func makeConfiguration() -> GlassConfiguration {
        var config = GlassConfiguration()
        config.applyStyle(style)
        config.physicsMode = physics
        return config
    }
}
