import Foundation

/// Current state of all spring-animated properties for a glass element.
///
/// Updated each frame by ``SpringPhysicsEngine`` based on touch input and velocity.
/// Each property has both a current value and velocity for spring simulation.
///
/// - SeeAlso: ``SpringPhysicsEngine``, ``PhysicsTouchState``
struct GlassAnimationState {
    /// Current scale factor (1.0 = normal size).
    var scale: Float = 1.0
    var scaleVelocity: Float = 0.0

    /// Current opacity (0.0 to 1.0).
    var opacity: Float = 1.0
    var opacityVelocity: Float = 0.0

    /// Horizontal stretch factor (1.0 = no stretch).
    var stretchX: Float = 1.0
    /// Vertical stretch factor.
    var stretchY: Float = 1.0
    var stretchXVelocity: Float = 0.0
    var stretchYVelocity: Float = 0.0

    /// Rotation angle in radians.
    var rotation: Float = 0.0
    var rotationVelocity: Float = 0.0

    /// Horizontal offset from physics (for anchored drag).
    var offsetX: Float = 0.0
    /// Vertical offset from physics.
    var offsetY: Float = 0.0
    var offsetXVelocity: Float = 0.0
    var offsetYVelocity: Float = 0.0

    /// Smoothed velocity for stretch calculations.
    var smoothedVelocityX: Float = 0.0
    var smoothedVelocityY: Float = 0.0

    /// Whether all animated properties have settled to rest.
    var isAtRest: Bool {
        abs(stretchX - 1.0) < 0.001
            && abs(stretchY - 1.0) < 0.001
            && abs(rotation) < 0.001
            && abs(offsetX) < 0.1
            && abs(offsetY) < 0.1
            && abs(scale - 1.0) < 0.001
    }
}

/// Namespace for spring physics simulation functions.
///
/// Implements damped harmonic oscillator physics for natural-feeling animations.
/// Supports multiple physics modes:
/// - **Free drag**: Stretch and rotate based on velocity
/// - **Anchored**: Stretch toward drag direction while staying in place
/// - **Bounded**: Constrained to axis/rect with edge overflow effects
///
/// Uses Euler integration with configurable stiffness and damping parameters.
/// Higher stiffness = faster response, higher damping = less oscillation.
///
/// - SeeAlso: ``GlassAnimationState``, ``OpenGlassPhysicsConfiguration``
enum SpringPhysicsEngine {
    /// Smoothing factor for velocity averaging (0-1, higher = faster response).
    static let velocitySmoothingFast: Float = 0.3

    /// Applies spring force to a single value toward a target.
    ///
    /// Uses Hooke's law with velocity damping: F = -kx - cv
    ///
    /// - Parameters:
    ///   - current: Current value (modified in place).
    ///   - velocity: Current velocity (modified in place).
    ///   - target: Target value to spring toward.
    ///   - stiffness: Spring constant (higher = faster).
    ///   - damping: Damping coefficient (higher = less bounce).
    ///   - deltaTime: Time step in seconds.
    static func applySpring(
        current: inout Float,
        velocity: inout Float,
        target: Float,
        stiffness: Float,
        damping: Float,
        deltaTime: Float,
    ) {
        let displacement = current - target
        let springForce = -stiffness * displacement
        let dampingForce = -damping * velocity
        let acceleration = springForce + dampingForce
        velocity += acceleration * deltaTime
        current += velocity * deltaTime
    }

    /// Applies spring force to an angular value with wraparound handling.
    ///
    /// Wraps displacement and result to [-π, π] for shortest-path rotation.
    static func applyAngularSpring(
        current: inout Float,
        velocity: inout Float,
        target: Float,
        stiffness: Float,
        damping: Float,
        deltaTime: Float,
    ) {
        var displacement = current - target
        let pi = Float.pi
        while displacement > pi {
            displacement -= 2 * pi
        }
        while displacement < -pi {
            displacement += 2 * pi
        }

        let springForce = -stiffness * displacement
        let dampingForce = -damping * velocity
        let acceleration = springForce + dampingForce
        velocity += acceleration * deltaTime
        current += velocity * deltaTime

        while current > pi {
            current -= 2 * pi
        }
        while current < -pi {
            current += 2 * pi
        }
    }

    /// Applies springs to both stretch axes.
    static func applyStretchSprings(
        state: inout GlassAnimationState,
        targetX: Float,
        targetY: Float,
        physics: OpenGlassPhysicsConfiguration,
        deltaTime: Float,
    ) {
        applySpring(current: &state.stretchX, velocity: &state.stretchXVelocity, target: targetX,
                    stiffness: physics.stretchSpringStiffness, damping: physics.stretchSpringDamping, deltaTime: deltaTime)
        applySpring(current: &state.stretchY, velocity: &state.stretchYVelocity, target: targetY,
                    stiffness: physics.stretchSpringStiffness, damping: physics.stretchSpringDamping, deltaTime: deltaTime)
    }

    /// Applies springs to both offset axes.
    static func applyOffsetSprings(
        state: inout GlassAnimationState,
        targetX: Float,
        targetY: Float,
        physics: OpenGlassPhysicsConfiguration,
        deltaTime: Float,
    ) {
        applySpring(current: &state.offsetX, velocity: &state.offsetXVelocity, target: targetX,
                    stiffness: physics.offsetSpringStiffness, damping: physics.offsetSpringDamping, deltaTime: deltaTime)
        applySpring(current: &state.offsetY, velocity: &state.offsetYVelocity, target: targetY,
                    stiffness: physics.offsetSpringStiffness, damping: physics.offsetSpringDamping, deltaTime: deltaTime)
    }

    static func applyRotationSpring(
        state: inout GlassAnimationState,
        target: Float,
        physics: OpenGlassPhysicsConfiguration,
        deltaTime: Float,
        angular: Bool = false,
    ) {
        if angular {
            applyAngularSpring(current: &state.rotation, velocity: &state.rotationVelocity, target: target,
                               stiffness: physics.rotationSpringStiffness, damping: physics.rotationSpringDamping, deltaTime: deltaTime)
        } else {
            applySpring(current: &state.rotation, velocity: &state.rotationVelocity, target: target,
                        stiffness: physics.rotationSpringStiffness, damping: physics.rotationSpringDamping, deltaTime: deltaTime)
        }
    }

    static func updateSmoothedVelocity(
        state: inout GlassAnimationState,
        instantVelocity: CGPoint,
    ) {
        let velX = Float(instantVelocity.x)
        let velY = Float(instantVelocity.y)
        state.smoothedVelocityX += velocitySmoothingFast * (velX - state.smoothedVelocityX)
        state.smoothedVelocityY += velocitySmoothingFast * (velY - state.smoothedVelocityY)
    }

    /// Updates physics for freely draggable elements.
    ///
    /// Stretches along velocity direction and compresses perpendicular.
    /// Rotation tilts opposite to horizontal velocity. Used when `bounds = .none`.
    static func updateFreeDragPhysics(
        state: inout GlassAnimationState,
        physics: OpenGlassPhysicsConfiguration,
        deltaTime: Float,
    ) {
        let velX = state.smoothedVelocityX
        let velY = state.smoothedVelocityY
        let speed = sqrt(velX * velX + velY * velY)

        var targetStretchX: Float = 1.0
        var targetStretchY: Float = 1.0
        var targetRotation: Float = 0.0

        if speed > 1 {
            let dirX = velX / speed
            let dirY = velY / speed

            let stretchAmount = min(speed * physics.velocityStretchSensitivity, physics.maxStretchAlongVelocity - 1.0)
            let compressAmount = 1.0 - min(speed * physics.velocityStretchSensitivity * 0.6, 1.0 - physics.minStretchPerpendicular)

            let absX = abs(dirX)
            let absY = abs(dirY)

            targetStretchX = 1.0 + stretchAmount * absX - (1.0 - compressAmount) * absY
            targetStretchY = 1.0 + stretchAmount * absY - (1.0 - compressAmount) * absX

            targetStretchX = max(physics.minStretchPerpendicular, min(physics.maxStretchAlongVelocity, targetStretchX))
            targetStretchY = max(physics.minStretchPerpendicular, min(physics.maxStretchAlongVelocity, targetStretchY))

            targetRotation = -velX * physics.velocityRotationSensitivity
            targetRotation = max(-physics.maxRotation, min(physics.maxRotation, targetRotation))
        }

        applyStretchSprings(state: &state, targetX: targetStretchX, targetY: targetStretchY, physics: physics, deltaTime: deltaTime)
        applyOffsetSprings(state: &state, targetX: 0, targetY: 0, physics: physics, deltaTime: deltaTime)
        applyRotationSpring(state: &state, target: targetRotation, physics: physics, deltaTime: deltaTime)
    }

    /// Updates physics for anchored elements that don't move.
    ///
    /// Stretches toward drag direction with asymptotic offset. Creates "tugging"
    /// feel where element resists being pulled but springs back on release.
    /// Used when `bounds = .anchored`.
    static func updateAnchoredPhysics(
        state: inout GlassAnimationState,
        physics: OpenGlassPhysicsConfiguration,
        touchState: PhysicsTouchState?,
        deltaTime: Float,
    ) {
        var targetStretchX: Float = 1.0
        var targetStretchY: Float = 1.0
        var targetOffsetX: Float = 0.0
        var targetOffsetY: Float = 0.0
        var targetRotation: Float = 0.0

        if let touch = touchState, touch.isActive {
            let dragX = Float(touch.dragOffset.x)
            let dragY = Float(touch.dragOffset.y)
            let dragDist = Float(touch.dragDistance)

            let pressSquish: Float = 0.97
            targetStretchX = pressSquish
            targetStretchY = pressSquish

            if dragDist > 1 {
                let dirX = dragX / dragDist
                let dirY = dragY / dragDist

                let stretchAmount = dragDist * physics.anchoredStretchSensitivity
                let clampedStretch = min(stretchAmount, physics.anchoredMaxStretch - 1.0)

                let xStretchFactor = abs(dirX) * abs(dirX)
                let yStretchFactor = abs(dirY) * abs(dirY)

                targetStretchX = pressSquish + clampedStretch * xStretchFactor - clampedStretch * 0.2 * yStretchFactor
                targetStretchY = pressSquish + clampedStretch * yStretchFactor - clampedStretch * 0.2 * xStretchFactor

                targetStretchX = max(0.85, targetStretchX)
                targetStretchY = max(0.85, targetStretchY)

                let offsetFactor = 1.0 - 1.0 / (1.0 + dragDist * physics.anchoredOffsetStiffness)
                targetOffsetX = physics.anchoredMaxOffset * offsetFactor * dirX
                targetOffsetY = physics.anchoredMaxOffset * offsetFactor * dirY

                targetRotation = -dirX * clampedStretch * 0.12
                targetRotation = max(-physics.maxRotation, min(physics.maxRotation, targetRotation))
            }
        }

        applyStretchSprings(state: &state, targetX: targetStretchX, targetY: targetStretchY, physics: physics, deltaTime: deltaTime)
        applyOffsetSprings(state: &state, targetX: targetOffsetX, targetY: targetOffsetY, physics: physics, deltaTime: deltaTime)
        applyRotationSpring(state: &state, target: targetRotation, physics: physics, deltaTime: deltaTime, angular: true)
    }

    /// Updates physics for bounded elements (horizontal, vertical, or rect).
    ///
    /// Combines velocity-based stretch (within bounds) with edge overflow effects
    /// (when hitting boundaries). Drag on locked axis creates anchored-style stretch.
    static func updateBoundedPhysics(
        state: inout GlassAnimationState,
        physics: OpenGlassPhysicsConfiguration,
        touchState: PhysicsTouchState?,
        deltaTime: Float,
    ) {
        let velX = state.smoothedVelocityX
        let velY = state.smoothedVelocityY

        var targetStretchX: Float = 1.0
        var targetStretchY: Float = 1.0
        var targetOffsetX: Float = 0.0
        var targetOffsetY: Float = 0.0
        var targetRotation: Float = 0.0

        var edgeOverflowX: Float = 0
        var edgeOverflowY: Float = 0
        var lockedAxisDragX: Float = 0
        var lockedAxisDragY: Float = 0
        var isHorizontalMode = false
        var isVerticalMode = false

        let pressSquish: Float = 0.97

        if let touch = touchState, touch.isActive {
            let dragX = Float(touch.dragOffset.x)
            let dragY = Float(touch.dragOffset.y)

            targetStretchX = pressSquish
            targetStretchY = pressSquish

            edgeOverflowX = Float(touch.edgeOverflow.x)
            edgeOverflowY = Float(touch.edgeOverflow.y)

            switch physics.bounds {
            case .horizontal:
                isHorizontalMode = true
                lockedAxisDragY = dragY
            case .vertical:
                isVerticalMode = true
                lockedAxisDragX = dragX
            case .rect, .none, .anchored:
                break
            }
        }

        let lockedDist = sqrt(lockedAxisDragX * lockedAxisDragX + lockedAxisDragY * lockedAxisDragY)
        if lockedDist > 1 {
            let dirX = lockedAxisDragX / lockedDist
            let dirY = lockedAxisDragY / lockedDist

            let stretchAmount = lockedDist * physics.anchoredStretchSensitivity
            let clampedStretch = min(stretchAmount, physics.anchoredMaxStretch - 1.0)

            targetStretchX = pressSquish + clampedStretch * dirX * dirX
            targetStretchY = pressSquish + clampedStretch * dirY * dirY

            let offsetFactor = 1.0 - 1.0 / (1.0 + lockedDist * physics.anchoredOffsetStiffness)
            targetOffsetX = physics.anchoredMaxOffset * offsetFactor * dirX
            targetOffsetY = physics.anchoredMaxOffset * offsetFactor * dirY

            targetRotation = -dirX * clampedStretch * 0.1
        }

        let edgeDist = sqrt(edgeOverflowX * edgeOverflowX + edgeOverflowY * edgeOverflowY)
        if edgeDist > 1 {
            let dirX = edgeOverflowX / edgeDist
            let dirY = edgeOverflowY / edgeDist

            let stretchAmount = edgeDist * physics.anchoredStretchSensitivity
            let clampedStretch = min(stretchAmount, physics.anchoredMaxStretch - 1.0)

            targetStretchX += clampedStretch * abs(dirX)
            targetStretchY += clampedStretch * abs(dirY)

            let offsetFactor = 1.0 - 1.0 / (1.0 + edgeDist * physics.anchoredOffsetStiffness)
            targetOffsetX += physics.anchoredMaxOffset * offsetFactor * dirX
            targetOffsetY += physics.anchoredMaxOffset * offsetFactor * dirY

            targetRotation += -dirX * clampedStretch * 0.1
        }

        let allowedVelX = isVerticalMode ? 0 : velX
        let allowedVelY = isHorizontalMode ? 0 : velY
        let allowedSpeed = sqrt(allowedVelX * allowedVelX + allowedVelY * allowedVelY)

        if edgeDist < 1, allowedSpeed > 1 {
            let dirX = allowedVelX / allowedSpeed
            let dirY = allowedVelY / allowedSpeed

            let stretchAmount = min(allowedSpeed * physics.velocityStretchSensitivity, physics.maxStretchAlongVelocity - 1.0)
            let compressAmount = 1.0 - min(allowedSpeed * physics.velocityStretchSensitivity * 0.6, 1.0 - physics.minStretchPerpendicular)

            let absX = abs(dirX)
            let absY = abs(dirY)

            if isHorizontalMode {
                targetStretchX = max(targetStretchX, 1.0 + stretchAmount * absX)
                if lockedDist < 1 { targetStretchY = min(targetStretchY, 1.0 - (1.0 - compressAmount) * absX) }
            } else if isVerticalMode {
                targetStretchY = max(targetStretchY, 1.0 + stretchAmount * absY)
                if lockedDist < 1 { targetStretchX = min(targetStretchX, 1.0 - (1.0 - compressAmount) * absY) }
            } else {
                targetStretchX = 1.0 + stretchAmount * absX - (1.0 - compressAmount) * absY
                targetStretchY = 1.0 + stretchAmount * absY - (1.0 - compressAmount) * absX
            }

            targetRotation = -allowedVelX * physics.velocityRotationSensitivity
        }

        targetStretchX = max(physics.minStretchPerpendicular, min(physics.anchoredMaxStretch, targetStretchX))
        targetStretchY = max(physics.minStretchPerpendicular, min(physics.anchoredMaxStretch, targetStretchY))
        targetRotation = max(-physics.maxRotation, min(physics.maxRotation, targetRotation))

        applyStretchSprings(state: &state, targetX: targetStretchX, targetY: targetStretchY, physics: physics, deltaTime: deltaTime)
        applyOffsetSprings(state: &state, targetX: targetOffsetX, targetY: targetOffsetY, physics: physics, deltaTime: deltaTime)
        applyRotationSpring(state: &state, target: targetRotation, physics: physics, deltaTime: deltaTime, angular: true)
    }

    /// Updates scale and opacity springs with touch-press effects.
    ///
    /// Applies pressed scale/opacity when touch is active, then springs back.
    /// Clamps opacity to [0, 1].
    static func updateScaleOpacitySpring(
        state: inout GlassAnimationState,
        config: GlassConfiguration,
        touchState: PhysicsTouchState?,
        physics: OpenGlassPhysicsConfiguration,
        deltaTime: Float,
    ) {
        var targetScale = config.targetScale
        var targetOpacity = config.targetOpacity

        if let touch = touchState, touch.isActive {
            targetScale *= physics.pressedScale
            targetOpacity *= physics.pressedOpacity
        }

        applySpring(current: &state.scale, velocity: &state.scaleVelocity, target: targetScale,
                    stiffness: config.scaleSpringStiffness, damping: config.scaleSpringDamping, deltaTime: deltaTime)
        applySpring(current: &state.opacity, velocity: &state.opacityVelocity, target: targetOpacity,
                    stiffness: config.opacitySpringStiffness, damping: config.opacitySpringDamping, deltaTime: deltaTime)

        state.opacity = max(0, min(1, state.opacity))
    }

    /// Main physics update entry point for standalone glass views.
    ///
    /// Selects the appropriate physics mode based on `config.physics.bounds` and
    /// updates all animation state for the frame. Called by ``SharedGlassCapture``
    /// each display link tick.
    ///
    /// - Parameters:
    ///   - state: Animation state to update (modified in place).
    ///   - config: Glass configuration with physics settings.
    ///   - touchState: Current touch state, if any.
    ///   - velocity: Current drag velocity from velocity tracker.
    ///   - deltaTime: Time step in seconds.
    static func updatePhysics(
        state: inout GlassAnimationState,
        config: GlassConfiguration,
        touchState: PhysicsTouchState?,
        velocity: CGPoint,
        deltaTime: Float,
    ) {
        let physics = config.physics

        updateSmoothedVelocity(state: &state, instantVelocity: velocity)

        switch physics.bounds {
        case .none:
            updateFreeDragPhysics(state: &state, physics: physics, deltaTime: deltaTime)
        case .anchored:
            updateAnchoredPhysics(state: &state, physics: physics, touchState: touchState, deltaTime: deltaTime)
        case .horizontal, .vertical, .rect:
            updateBoundedPhysics(state: &state, physics: physics, touchState: touchState, deltaTime: deltaTime)
        }

        updateScaleOpacitySpring(state: &state, config: config, touchState: touchState, physics: physics, deltaTime: deltaTime)
    }
}
