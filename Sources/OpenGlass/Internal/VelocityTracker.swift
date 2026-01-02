import Foundation

/// Tracks smoothed velocities for glass view motion.
///
/// Computes velocity from position changes each frame, applying exponential
/// smoothing to reduce noise. Used by ``SpringPhysicsEngine`` for velocity-based
/// stretch and rotation effects.
///
/// Smoothing formula: `v = v + factor * (instantV - v)`
///
/// - Note: Internal class used by ``SharedGlassCapture``.
/// - SeeAlso: ``SharedGlassCapture``, ``SpringPhysicsEngine``
@MainActor
final class VelocityTracker {
    private var velocities: [ObjectIdentifier: CGPoint] = [:]
    private var previousPositions: [ObjectIdentifier: CGPoint] = [:]

    private let smoothingFactor: CGFloat

    /// Creates a tracker with the specified smoothing factor.
    ///
    /// - Parameter smoothingFactor: Blend weight for new velocity samples (0-1).
    ///   Higher values = faster response but more noise. Default: 0.6.
    init(smoothingFactor: CGFloat = 0.6) {
        self.smoothingFactor = smoothingFactor
    }

    /// Updates velocity based on position change since last frame.
    ///
    /// - Parameters:
    ///   - id: Identifier of the tracked element.
    ///   - currentPosition: Current position in points.
    ///   - deltaTime: Time since last update in seconds.
    func update(id: ObjectIdentifier, currentPosition: CGPoint, deltaTime: CFTimeInterval) {
        guard deltaTime > 0 else { return }

        if let previousPosition = previousPositions[id] {
            let instantVelocity = CGPoint(
                x: (currentPosition.x - previousPosition.x) / deltaTime,
                y: (currentPosition.y - previousPosition.y) / deltaTime,
            )

            if let existingVelocity = velocities[id] {
                velocities[id] = CGPoint(
                    x: existingVelocity.x + smoothingFactor * (instantVelocity.x - existingVelocity.x),
                    y: existingVelocity.y + smoothingFactor * (instantVelocity.y - existingVelocity.y),
                )
            } else {
                velocities[id] = instantVelocity
            }
        }

        previousPositions[id] = currentPosition
    }

    /// Sets velocity directly (e.g., from gesture recognizer).
    func setVelocity(id: ObjectIdentifier, velocity: CGPoint) {
        velocities[id] = velocity
    }

    /// Returns the current smoothed velocity for an element.
    func velocity(for id: ObjectIdentifier) -> CGPoint {
        velocities[id] ?? .zero
    }

    /// Removes tracking state for an element.
    func remove(id: ObjectIdentifier) {
        velocities.removeValue(forKey: id)
        previousPositions.removeValue(forKey: id)
    }

    /// Clears all tracking state.
    func reset() {
        velocities.removeAll()
        previousPositions.removeAll()
    }
}
