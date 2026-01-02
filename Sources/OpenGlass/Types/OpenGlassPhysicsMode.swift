import Foundation

/// Movement constraints for physics-enabled glass elements.
///
/// Controls how the glass element responds to drag gestures.
///
/// - SeeAlso: ``OpenGlassPhysicsConfiguration``, ``OpenGlass/physicsBounds(_:)``
public enum OpenGlassPhysicsBounds: Equatable, Sendable {
    /// Free movement in any direction.
    case none
    /// Anchored to origin with stretch feedback. Springs back on release.
    case anchored
    /// Constrained to horizontal axis within bounds.
    case horizontal(min: CGFloat, max: CGFloat)
    /// Constrained to vertical axis within bounds.
    case vertical(min: CGFloat, max: CGFloat)
    /// Constrained within a rectangle.
    case rect(CGRect)
}

/// Complete physics configuration for touch interactions.
///
/// Controls all aspects of physics behavior including stretch, rotation, and spring
/// parameters. Default values provide a natural, fluid feel.
///
/// **Example**:
/// ```swift
/// var physics = OpenGlassPhysicsConfiguration()
/// physics.pressedScale = 1.05
/// physics.velocityStretchSensitivity = 0.001
/// physics.maxStretchAlongVelocity = 1.2
/// ```
///
/// - SeeAlso: ``OpenGlassPhysicsBounds``, ``OpenGlass/physics(_:)``
public struct OpenGlassPhysicsConfiguration: Equatable, Sendable {
    /// Movement constraint mode.
    public var bounds: OpenGlassPhysicsBounds

    // MARK: - Velocity Stretch

    /// How much velocity affects stretch amount.
    public var velocityStretchSensitivity: Float = 0.0006
    /// Maximum stretch along velocity direction (1.0 = no stretch).
    public var maxStretchAlongVelocity: Float = 1.12
    /// Minimum stretch perpendicular to velocity (squash effect).
    public var minStretchPerpendicular: Float = 0.92
    /// Spring stiffness for stretch recovery.
    public var stretchSpringStiffness: Float = 220.0
    /// Spring damping for stretch recovery.
    public var stretchSpringDamping: Float = 16.0

    // MARK: - Anchored Mode

    /// Stretch sensitivity when anchored.
    public var anchoredStretchSensitivity: Float = 0.0008
    /// Maximum stretch when anchored.
    public var anchoredMaxStretch: Float = 1.08
    /// Maximum visual offset when anchored (springs back).
    public var anchoredMaxOffset: Float = 12.0
    /// Offset spring stiffness when anchored.
    public var anchoredOffsetStiffness: Float = 0.006

    // MARK: - Rotation

    /// How much velocity affects rotation.
    public var velocityRotationSensitivity: Float = 0.0
    /// Maximum rotation angle in radians.
    public var maxRotation: Float = 0.0
    /// Spring stiffness for rotation recovery.
    public var rotationSpringStiffness: Float = 200.0
    /// Spring damping for rotation recovery.
    public var rotationSpringDamping: Float = 14.0

    // MARK: - Position

    /// Spring stiffness for position recovery.
    public var offsetSpringStiffness: Float = 280.0
    /// Spring damping for position recovery.
    public var offsetSpringDamping: Float = 20.0

    // MARK: - Press State

    /// Scale when pressed/held (1.0 = no change).
    public var pressedScale: Float = 1.12
    /// Opacity when pressed/held (1.0 = fully opaque).
    public var pressedOpacity: Float = 1.0

    /// Creates a physics configuration with the specified bounds.
    ///
    /// - Parameter bounds: Movement constraint mode. Default: `.none` (free movement).
    public init(bounds: OpenGlassPhysicsBounds = .none) {
        self.bounds = bounds
    }
}

/// Internal state for tracking touch gestures.
///
/// Used by the physics engine to compute velocities and drag offsets.
struct PhysicsTouchState {
    var isActive: Bool = false
    var startPosition: CGPoint = .zero
    var currentPosition: CGPoint = .zero
    var previousPosition: CGPoint = .zero
    var timestamp: CFTimeInterval = 0
    var edgeOverflow: CGPoint = .zero

    var dragOffset: CGPoint {
        CGPoint(
            x: currentPosition.x - startPosition.x,
            y: currentPosition.y - startPosition.y,
        )
    }

    var dragDistance: CGFloat {
        sqrt(dragOffset.x * dragOffset.x + dragOffset.y * dragOffset.y)
    }

    var dragDirection: CGPoint {
        let dist = dragDistance
        guard dist > 0.001 else { return .zero }
        return CGPoint(x: dragOffset.x / dist, y: dragOffset.y / dist)
    }
}
