import SwiftUI

// MARK: - Environment Keys

/// Environment key for container spacing value.
struct OpenGlassContainerSpacingKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

/// Environment key indicating whether view is inside a glass container.
struct OpenGlassContainerActiveKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

/// Environment key for the container's coordinator.
struct OpenGlassContainerCoordinatorKey: EnvironmentKey {
    static let defaultValue: GlassContainerCoordinator? = nil
}

// MARK: - Environment Values

extension EnvironmentValues {
    /// The spacing value from the enclosing ``OpenGlassEffectContainer``, if any.
    var openGlassContainerSpacing: CGFloat? {
        get { self[OpenGlassContainerSpacingKey.self] }
        set { self[OpenGlassContainerSpacingKey.self] = newValue }
    }

    /// Whether the view is inside an ``OpenGlassEffectContainer``.
    ///
    /// Used by ``OpenGlassModifier`` to determine which rendering path to use.
    var openGlassContainerActive: Bool {
        get { self[OpenGlassContainerActiveKey.self] }
        set { self[OpenGlassContainerActiveKey.self] = newValue }
    }

    /// The coordinator for the enclosing container, if any.
    ///
    /// Child glass views register with this coordinator for morphing effects.
    var openGlassContainerCoordinator: GlassContainerCoordinator? {
        get { self[OpenGlassContainerCoordinatorKey.self] }
        set { self[OpenGlassContainerCoordinatorKey.self] = newValue }
    }
}
