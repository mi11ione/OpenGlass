import UIKit

/// Handles touch gestures for physics-driven glass animations.
///
/// Attaches long-press and pan gesture recognizers to a view and forwards touch
/// state to ``SharedGlassCapture`` for physics simulation. Supports both standalone
/// glass views and container children.
///
/// The handler:
/// - Tracks touch position relative to view center for stretch direction
/// - Computes edge overflow when dragging against bounds
/// - Forwards gesture velocity for velocity-based stretch effects
///
/// - Note: Gestures are non-exclusive (simultaneous recognition allowed).
/// - SeeAlso: ``SharedGlassCapture``, ``SpringPhysicsEngine``
@MainActor
final class GlassPhysicsGestureHandler: NSObject, UIGestureRecognizerDelegate {
    /// Target element receiving touch state updates.
    enum Target {
        case glassView(OpenGlassView)
        case containerChild(ObjectIdentifier)
    }

    private weak var view: UIView?
    private let target: Target
    private var pressGesture: UILongPressGestureRecognizer?
    private var panGesture: UIPanGestureRecognizer?
    private var dragStartPosition: CGPoint = .zero

    /// Whether gesture recognition is enabled.
    var isEnabled: Bool = true {
        didSet {
            pressGesture?.isEnabled = isEnabled
            panGesture?.isEnabled = isEnabled
        }
    }

    /// Creates a handler for a standalone glass view.
    ///
    /// - Parameters:
    ///   - view: View to attach gestures to.
    ///   - glassView: Glass view to receive touch state.
    init(attachTo view: UIView, glassView: OpenGlassView) {
        self.view = view
        target = .glassView(glassView)
        super.init()
        setupGestures()
    }

    /// Creates a handler for a container child element.
    ///
    /// - Parameters:
    ///   - view: View to attach gestures to.
    ///   - childId: Identifier of the container child.
    init(attachTo view: UIView, childId: ObjectIdentifier) {
        self.view = view
        target = .containerChild(childId)
        super.init()
        setupGestures()
    }

    private func setupGestures() {
        guard let view else { return }

        let press = UILongPressGestureRecognizer(target: self, action: #selector(handlePress(_:)))
        press.minimumPressDuration = 0
        press.cancelsTouchesInView = false
        press.delaysTouchesBegan = false
        press.delegate = self
        view.addGestureRecognizer(press)
        pressGesture = press

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 1
        pan.cancelsTouchesInView = false
        pan.delaysTouchesBegan = false
        pan.delegate = self
        view.addGestureRecognizer(pan)
        panGesture = pan
    }

    @objc private func handlePress(_ gesture: UILongPressGestureRecognizer) {
        guard let view else { return }

        let location = gesture.location(in: view)
        let center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        let relativePosition = CGPoint(x: location.x - center.x, y: location.y - center.y)

        switch gesture.state {
        case .began:
            if case let .glassView(glassView) = target {
                dragStartPosition = glassView.currentPosition
            }
            updateTouchState(isActive: true, position: relativePosition, edgeOverflow: .zero)

        case .ended, .cancelled, .failed:
            updateTouchState(isActive: false, position: relativePosition, edgeOverflow: .zero)

        default:
            break
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let view else { return }

        let location = gesture.location(in: view)
        let center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        let relativePosition = CGPoint(x: location.x - center.x, y: location.y - center.y)
        let gestureVelocity = gesture.velocity(in: view.superview)

        switch gesture.state {
        case .began:
            if case let .glassView(glassView) = target {
                SharedGlassCapture.shared.setDragVelocity(for: glassView, velocity: gestureVelocity)
            }

        case .changed:
            var edgeOverflow = CGPoint.zero

            if case let .glassView(glassView) = target {
                let physics = glassView.configuration.physics
                let translation = gesture.translation(in: view.superview)

                switch physics.bounds {
                case .none:
                    let newPosition = CGPoint(
                        x: dragStartPosition.x + translation.x,
                        y: dragStartPosition.y + translation.y,
                    )
                    glassView.currentPosition = newPosition
                    glassView.onPositionChange?(newPosition)

                case let .horizontal(minX, maxX):
                    let unclampedX = dragStartPosition.x + translation.x
                    let newX = max(minX, min(maxX, unclampedX))
                    edgeOverflow.x = unclampedX - newX
                    let newPosition = CGPoint(x: newX, y: dragStartPosition.y)
                    glassView.currentPosition = newPosition
                    glassView.onPositionChange?(newPosition)

                case let .vertical(minY, maxY):
                    let unclampedY = dragStartPosition.y + translation.y
                    let newY = max(minY, min(maxY, unclampedY))
                    edgeOverflow.y = unclampedY - newY
                    let newPosition = CGPoint(x: dragStartPosition.x, y: newY)
                    glassView.currentPosition = newPosition
                    glassView.onPositionChange?(newPosition)

                case let .rect(rect):
                    let unclampedX = dragStartPosition.x + translation.x
                    let unclampedY = dragStartPosition.y + translation.y
                    let newX = max(rect.minX, min(rect.maxX, unclampedX))
                    let newY = max(rect.minY, min(rect.maxY, unclampedY))
                    edgeOverflow.x = unclampedX - newX
                    edgeOverflow.y = unclampedY - newY
                    let newPosition = CGPoint(x: newX, y: newY)
                    glassView.currentPosition = newPosition
                    glassView.onPositionChange?(newPosition)

                case .anchored:
                    break
                }

                SharedGlassCapture.shared.setDragVelocity(for: glassView, velocity: gestureVelocity)
            }

            updateTouchState(isActive: true, position: relativePosition, edgeOverflow: edgeOverflow)

        case .ended, .cancelled, .failed:
            if case let .glassView(glassView) = target {
                SharedGlassCapture.shared.setDragVelocity(for: glassView, velocity: .zero)
            }
            updateTouchState(isActive: false, position: relativePosition, edgeOverflow: .zero)

        default:
            break
        }
    }

    private func updateTouchState(isActive: Bool, position: CGPoint, edgeOverflow: CGPoint) {
        switch target {
        case let .glassView(glassView):
            SharedGlassCapture.shared.updateTouchState(for: glassView, isActive: isActive, position: position, edgeOverflow: edgeOverflow)
        case let .containerChild(childId):
            SharedGlassCapture.shared.updateContainerChildTouchState(id: childId, isActive: isActive, position: position)
        }
    }

    func gestureRecognizer(
        _: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer,
    ) -> Bool {
        true
    }
}
