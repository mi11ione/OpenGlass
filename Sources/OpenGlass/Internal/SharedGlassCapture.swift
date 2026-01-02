import MetalKit

/// Central coordinator for all glass view rendering and physics simulation.
///
/// `SharedGlassCapture` is a singleton that manages the render loop for all glass views
/// in the application. It coordinates:
/// - **Screen capture**: Single capture per frame shared across all glass views
/// - **Physics simulation**: Spring-based animations for scale, stretch, rotation
/// - **Display link**: 60/120Hz render loop tied to screen refresh
/// - **Resource management**: Automatic cleanup when views are removed
///
/// Glass views register with this singleton when added to the window and unregister
/// when removed. The display link starts automatically when the first view registers
/// and stops when the last view unregisters.
///
/// - Note: Internal singleton. Glass views register/unregister automatically.
/// - SeeAlso: ``OpenGlassView``, ``OpenGlassContainerRenderView``, ``SpringPhysicsEngine``
@MainActor
final class SharedGlassCapture {
    /// Shared singleton instance.
    static let shared = SharedGlassCapture()

    private var registeredViews: [WeakRef<OpenGlassView>] = []
    private var registeredContainers: [WeakRef<OpenGlassContainerRenderView>] = []
    private var displayLink: CADisplayLink?

    private let textureCapture: GlassTextureCapture?
    private let velocityTracker = VelocityTracker()
    private let snapshotManager = ContentSnapshotManager()

    private var animationStates: [ObjectIdentifier: GlassAnimationState] = [:]
    private var touchStates: [ObjectIdentifier: PhysicsTouchState] = [:]

    private var containerChildConfigs: [ObjectIdentifier: ContainerChildConfig] = [:]
    private var containerChildAnimations: [ObjectIdentifier: GlassAnimationState] = [:]
    private var containerChildTouchStates: [ObjectIdentifier: PhysicsTouchState] = [:]

    private var previousTimestamp: CFTimeInterval = 0

    private struct WeakRef<T: AnyObject> {
        weak var value: T?
    }

    /// Configuration for a container child, linking to its coordinator and glass settings.
    struct ContainerChildConfig {
        weak var coordinator: GlassContainerCoordinator?
        var config: GlassConfiguration
    }

    private enum Constants {
        static let capturePadding: CGFloat = 30
        static let maxDeltaTime: Float = 0.05
        static let minDeltaTime: Float = 0.001
        static let defaultDeltaTime: Float = 0.016
    }

    private init() {
        let device = MTLCreateSystemDefaultDevice()
        textureCapture = GlassTextureCapture(device: device)
    }

    /// Registers a standalone glass view for rendering.
    ///
    /// Called automatically by `OpenGlassView.didMoveToWindow()`. Starts the display
    /// link if this is the first registered view.
    func register(_ view: OpenGlassView) {
        cleanupDeadRefs()
        guard !registeredViews.contains(where: { $0.value === view }) else { return }
        registeredViews.append(WeakRef(value: view))
        startDisplayLinkIfNeeded()
    }

    /// Unregisters a standalone glass view.
    ///
    /// Cleans up all associated state (velocity, animation, touch, snapshots).
    /// Stops the display link if no views remain.
    func unregister(_ view: OpenGlassView) {
        let viewId = ObjectIdentifier(view)
        registeredViews.removeAll { $0.value == nil || $0.value === view }
        velocityTracker.remove(id: viewId)
        animationStates.removeValue(forKey: viewId)
        touchStates.removeValue(forKey: viewId)
        snapshotManager.remove(id: viewId, contentView: view.contentViewToHide)
        stopDisplayLinkIfEmpty()
    }

    /// Registers a container view for rendering.
    ///
    /// Containers manage multiple child glass elements with morphing effects.
    func registerContainer(_ container: OpenGlassContainerRenderView) {
        cleanupDeadContainerRefs()
        guard !registeredContainers.contains(where: { $0.value === container }) else { return }
        registeredContainers.append(WeakRef(value: container))
        startDisplayLinkIfNeeded()
    }

    /// Unregisters a container view.
    func unregisterContainer(_ container: OpenGlassContainerRenderView) {
        registeredContainers.removeAll { $0.value == nil || $0.value === container }
        stopDisplayLinkIfEmpty()
    }

    /// Registers a child element within a container.
    ///
    /// Creates animation state for the child and links it to its coordinator.
    func registerContainerChild(
        id: ObjectIdentifier,
        coordinator: GlassContainerCoordinator,
        config: GlassConfiguration,
    ) {
        containerChildConfigs[id] = ContainerChildConfig(coordinator: coordinator, config: config)
        containerChildAnimations[id] = GlassAnimationState()
    }

    /// Unregisters a container child, cleaning up all associated state.
    func unregisterContainerChild(id: ObjectIdentifier) {
        let contentView = containerChildConfigs[id]?.coordinator?.getChildContentView(id: id)
        containerChildConfigs.removeValue(forKey: id)
        containerChildAnimations.removeValue(forKey: id)
        containerChildTouchStates.removeValue(forKey: id)
        snapshotManager.remove(id: id, contentView: contentView)
    }

    /// Updates the configuration for a container child.
    func updateContainerChildConfig(id: ObjectIdentifier, config: GlassConfiguration) {
        guard var childConfig = containerChildConfigs[id] else { return }
        childConfig.config = config
        containerChildConfigs[id] = childConfig
    }

    /// Updates touch state for a standalone glass view.
    ///
    /// Called by the gesture handler on touch begin, move, and end events.
    /// Records position history for physics calculations.
    func updateTouchState(for view: OpenGlassView, isActive: Bool, position: CGPoint, edgeOverflow: CGPoint = .zero) {
        let viewId = ObjectIdentifier(view)
        var state = touchStates[viewId] ?? PhysicsTouchState()

        if isActive, !state.isActive {
            state.startPosition = position
            state.previousPosition = position
        }

        state.isActive = isActive
        state.previousPosition = state.currentPosition
        state.currentPosition = position
        state.edgeOverflow = edgeOverflow
        state.timestamp = CACurrentMediaTime()

        touchStates[viewId] = state
    }

    /// Updates touch state for a container child element.
    func updateContainerChildTouchState(id: ObjectIdentifier, isActive: Bool, position: CGPoint) {
        var state = containerChildTouchStates[id] ?? PhysicsTouchState()

        if isActive, !state.isActive {
            state.startPosition = position
            state.previousPosition = position
        }

        state.isActive = isActive
        state.previousPosition = state.currentPosition
        state.currentPosition = position
        state.timestamp = CACurrentMediaTime()

        containerChildTouchStates[id] = state
    }

    /// Sets the drag velocity for a glass view from gesture recognizer.
    func setDragVelocity(for view: OpenGlassView, velocity: CGPoint) {
        velocityTracker.setVelocity(id: ObjectIdentifier(view), velocity: velocity)
    }

    private func startDisplayLinkIfNeeded() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLinkIfEmpty() {
        cleanupDeadRefs()
        cleanupDeadContainerRefs()
        guard registeredViews.isEmpty, registeredContainers.isEmpty else { return }
        displayLink?.invalidate()
        displayLink = nil
        releaseResources()
    }

    private func releaseResources() {
        textureCapture?.releaseResources()
        velocityTracker.reset()
        animationStates.removeAll()
        touchStates.removeAll()
        snapshotManager.removeAll()
        previousTimestamp = 0
    }

    private func cleanupDeadRefs() {
        registeredViews.removeAll { $0.value == nil }
    }

    private func cleanupDeadContainerRefs() {
        registeredContainers.removeAll { $0.value == nil }
    }

    @objc private func tick(_ displayLink: CADisplayLink) {
        let currentTimestamp = CACurrentMediaTime()
        let rawDelta = previousTimestamp > 0 ? Float(currentTimestamp - previousTimestamp) : Constants.defaultDeltaTime
        let deltaTime = max(Constants.minDeltaTime, min(Constants.maxDeltaTime, rawDelta))

        processStandaloneViews(displayLink: displayLink, deltaTime: deltaTime)
        processContainers(deltaTime: deltaTime)

        previousTimestamp = currentTimestamp
    }

    private func processStandaloneViews(displayLink: CADisplayLink, deltaTime: Float) {
        let activeViews = registeredViews.compactMap(\.value)
        guard !activeViews.isEmpty else { return }
        guard let sourceView = findSourceView(for: activeViews) else { return }

        updateViewVelocities(for: activeViews, in: sourceView, deltaTime: CFTimeInterval(deltaTime))
        updateViewPhysics(for: activeViews, deltaTime: deltaTime)

        let unionRect = calculateUnionCaptureRect(for: activeViews, in: sourceView)
        guard unionRect.width > 0, unionRect.height > 0 else { return }

        let viewsToRestore = hideViewsForCapture(activeViews)
        let texture = textureCapture?.capture(sourceView: sourceView, rect: unionRect)
        restoreViews(viewsToRestore)

        guard let sharedTexture = texture else { return }

        let frameDuration = displayLink.targetTimestamp - CACurrentMediaTime()
        distributeTexture(sharedTexture, captureRect: unionRect, to: activeViews, sourceView: sourceView, frameDuration: frameDuration)
    }

    private func updateViewVelocities(for views: [OpenGlassView], in sourceView: UIView, deltaTime: CFTimeInterval) {
        for view in views {
            let frameInSource = view.convert(view.bounds, to: sourceView)
            velocityTracker.update(id: ObjectIdentifier(view), currentPosition: frameInSource.origin, deltaTime: deltaTime)
        }
    }

    private func updateViewPhysics(for views: [OpenGlassView], deltaTime: Float) {
        for view in views {
            let viewId = ObjectIdentifier(view)
            var state = animationStates[viewId] ?? GlassAnimationState()
            let touchState = touchStates[viewId]
            let velocity = velocityTracker.velocity(for: viewId)

            SpringPhysicsEngine.updatePhysics(
                state: &state,
                config: view.configuration,
                touchState: touchState,
                velocity: velocity,
                deltaTime: deltaTime,
            )

            animationStates[viewId] = state
        }
    }

    private func hideAndRecord(_ view: UIView, into list: inout [(UIView, Bool)]) {
        list.append((view, view.isHidden))
        view.isHidden = true
    }

    private func hideViewsForCapture(_ views: [OpenGlassView]) -> [(UIView, Bool)] {
        var result: [(UIView, Bool)] = []
        for glassView in views {
            hideAndRecord(glassView, into: &result)
            if let contentView = glassView.contentViewToHide {
                hideAndRecord(contentView, into: &result)
            }
            if let snapshot = snapshotManager.snapshot(for: ObjectIdentifier(glassView)) {
                hideAndRecord(snapshot, into: &result)
            }
        }
        return result
    }

    private func restoreViews(_ viewsToRestore: [(UIView, Bool)]) {
        for (view, wasHidden) in viewsToRestore {
            view.isHidden = wasHidden
        }
    }

    private func distributeTexture(
        _ texture: MTLTexture,
        captureRect: CGRect,
        to views: [OpenGlassView],
        sourceView: UIView,
        frameDuration _: CFTimeInterval,
    ) {
        for view in views {
            let viewId = ObjectIdentifier(view)
            let frameInSource = view.convert(view.bounds, to: sourceView)

            let offsetInCapture = CGPoint(
                x: frameInSource.origin.x - captureRect.origin.x,
                y: frameInSource.origin.y - captureRect.origin.y,
            )

            let state = animationStates[viewId] ?? GlassAnimationState()

            view.renderWithSharedCapture(
                texture: texture,
                captureSize: captureRect.size,
                offset: offsetInCapture,
                animatedScale: state.scale,
                animatedOpacity: state.opacity,
                animatedStretchX: state.stretchX,
                animatedStretchY: state.stretchY,
                animatedRotation: state.rotation,
                animatedOffsetX: state.offsetX,
                animatedOffsetY: state.offsetY,
            )

            if let contentView = view.contentViewToHide {
                let touchState = touchStates[viewId]
                snapshotManager.applyTransform(
                    to: contentView,
                    id: viewId,
                    state: state,
                    isActive: touchState?.isActive ?? false,
                )
            }
        }
    }

    private func processContainers(deltaTime: Float) {
        let activeContainers = registeredContainers.compactMap(\.value)
        guard !activeContainers.isEmpty else { return }

        updateContainerChildrenPhysics(deltaTime: deltaTime)

        for container in activeContainers {
            captureAndRenderContainer(container)
        }
    }

    private func updateContainerChildrenPhysics(deltaTime: Float) {
        for (id, childConfig) in containerChildConfigs {
            guard let coordinator = childConfig.coordinator else {
                containerChildConfigs.removeValue(forKey: id)
                continue
            }

            var state = containerChildAnimations[id] ?? GlassAnimationState()
            let touchState = containerChildTouchStates[id]

            SpringPhysicsEngine.updateAnchoredPhysics(
                state: &state,
                physics: childConfig.config.physics,
                touchState: touchState,
                deltaTime: deltaTime,
            )

            SpringPhysicsEngine.updateScaleOpacitySpring(
                state: &state,
                config: childConfig.config,
                touchState: touchState,
                physics: childConfig.config.physics,
                deltaTime: deltaTime,
            )

            containerChildAnimations[id] = state

            coordinator.containerView?.updateChildPhysics(
                id: id,
                stretchX: state.stretchX,
                stretchY: state.stretchY,
                rotation: state.rotation,
                physicsOffset: CGPoint(x: CGFloat(state.offsetX), y: CGFloat(state.offsetY)),
                scale: state.scale,
                opacity: state.opacity,
            )

            if let contentView = coordinator.getChildContentView(id: id) {
                snapshotManager.applyTransform(
                    to: contentView,
                    id: id,
                    state: state,
                    isActive: touchState?.isActive ?? false,
                )
            }
        }
    }

    private func captureAndRenderContainer(_ container: OpenGlassContainerRenderView) {
        guard let sourceView = findSourceView(for: container) else { return }

        let containerFrame = container.convert(container.bounds, to: sourceView)
        let captureRect = containerFrame.insetBy(dx: -Constants.capturePadding, dy: -Constants.capturePadding)
            .intersection(sourceView.bounds)

        guard captureRect.width > 0, captureRect.height > 0 else { return }

        let viewsToRestore = hideContainerViewsForCapture(container)
        let texture = textureCapture?.capture(sourceView: sourceView, rect: captureRect)
        restoreViews(viewsToRestore)

        guard let sharedTexture = texture else { return }

        let offsetInCapture = CGPoint(
            x: containerFrame.origin.x - captureRect.origin.x,
            y: containerFrame.origin.y - captureRect.origin.y,
        )

        container.renderWithSharedCapture(
            texture: sharedTexture,
            captureSize: captureRect.size,
            offset: offsetInCapture,
        )
    }

    private func hideContainerViewsForCapture(_ container: OpenGlassContainerRenderView) -> [(UIView, Bool)] {
        var result: [(UIView, Bool)] = []
        if let metalView = container.subviews.first(where: { $0 is MTKView }) {
            hideAndRecord(metalView, into: &result)
        }
        for contentView in container.getContentViewsToHide() {
            hideAndRecord(contentView, into: &result)
        }
        for childView in container.getChildViews() {
            hideAndRecord(childView, into: &result)
        }
        for (id, snapshot) in snapshotManager.allSnapshots() where containerChildConfigs[id] != nil {
            hideAndRecord(snapshot, into: &result)
        }
        return result
    }

    private func findSourceView(explicit: UIView?, window: UIWindow?) -> UIView? {
        if let source = explicit { return source }
        return window?.rootViewController?.view ?? window
    }

    private func findSourceView(for views: [OpenGlassView]) -> UIView? {
        guard let firstView = views.first else { return nil }
        return findSourceView(explicit: firstView.sourceView, window: firstView.window)
    }

    private func findSourceView(for container: OpenGlassContainerRenderView) -> UIView? {
        findSourceView(explicit: container.sourceView, window: container.window)
    }

    private func calculateUnionCaptureRect(for views: [OpenGlassView], in sourceView: UIView) -> CGRect {
        var unionRect = CGRect.null
        for view in views {
            let frameInSource = view.convert(view.bounds, to: sourceView)
            let paddedRect = frameInSource.insetBy(dx: -Constants.capturePadding, dy: -Constants.capturePadding)
            unionRect = unionRect.union(paddedRect)
        }
        return unionRect.intersection(sourceView.bounds)
    }
}
