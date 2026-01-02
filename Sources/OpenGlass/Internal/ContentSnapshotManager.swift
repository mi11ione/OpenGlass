import UIKit

/// Manages snapshot images of content views for physics-driven transforms.
///
/// When a glass element's content needs to animate with physics (stretch, rotate,
/// scale), the original content view can't be transformed directly because it would
/// break layout. Instead, this manager:
///
/// 1. Creates a rasterized snapshot of the content on touch begin
/// 2. Hides the original content view
/// 3. Applies transforms to the snapshot each frame
/// 4. Removes the snapshot and restores the original when animation completes
///
/// This provides smooth physics animations without affecting the actual view hierarchy.
///
/// - Note: Internal class used by ``SharedGlassCapture``.
/// - SeeAlso: ``SharedGlassCapture``, ``GlassAnimationState``
@MainActor
final class ContentSnapshotManager {
    private var snapshots: [ObjectIdentifier: UIView] = [:]
    private var activeStates: [ObjectIdentifier: Bool] = [:]

    /// Applies physics transform to a content view via its snapshot.
    ///
    /// Creates a snapshot on first activation, applies transform each frame,
    /// and removes snapshot when animation settles to rest.
    ///
    /// - Parameters:
    ///   - contentView: The original content view.
    ///   - id: Unique identifier for tracking.
    ///   - state: Current animation state with transform values.
    ///   - isActive: Whether touch is currently active.
    func applyTransform(
        to contentView: UIView,
        id: ObjectIdentifier,
        state: GlassAnimationState,
        isActive: Bool,
    ) {
        let wasActive = activeStates[id] ?? false

        if isActive, !wasActive {
            createSnapshot(for: contentView, id: id)
        }

        if let snapshot = snapshots[id] {
            let transform = CGAffineTransform.identity
                .translatedBy(x: CGFloat(state.offsetX), y: CGFloat(state.offsetY))
                .rotated(by: CGFloat(state.rotation))
                .scaledBy(x: CGFloat(state.stretchX * state.scale), y: CGFloat(state.stretchY * state.scale))
            snapshot.transform = transform
            snapshot.alpha = CGFloat(state.opacity)

            if !isActive, state.isAtRest {
                removeSnapshot(for: contentView, id: id)
            }
        }

        activeStates[id] = isActive
    }

    /// Removes a snapshot and restores the original content view.
    func remove(id: ObjectIdentifier, contentView: UIView?) {
        if let snapshot = snapshots[id] {
            snapshot.removeFromSuperview()
            snapshots.removeValue(forKey: id)
        }
        activeStates.removeValue(forKey: id)

        if let contentView {
            contentView.isHidden = false
            contentView.transform = .identity
            contentView.alpha = 1.0
        }
    }

    /// Removes all snapshots and clears state.
    func removeAll() {
        for snapshot in snapshots.values {
            snapshot.removeFromSuperview()
        }
        snapshots.removeAll()
        activeStates.removeAll()
    }

    /// Returns the snapshot view for an ID, if one exists.
    func snapshot(for id: ObjectIdentifier) -> UIView? {
        snapshots[id]
    }

    /// Returns all active snapshots.
    func allSnapshots() -> [ObjectIdentifier: UIView] {
        snapshots
    }

    private func createSnapshot(for contentView: UIView, id: ObjectIdentifier) {
        guard snapshots[id] == nil else { return }
        guard let superview = contentView.superview else { return }

        let renderer = UIGraphicsImageRenderer(bounds: contentView.bounds)
        let image = renderer.image { context in
            contentView.layer.render(in: context.cgContext)
        }

        let snapshotView = UIImageView(image: image)
        snapshotView.frame = contentView.frame
        snapshotView.contentMode = .scaleToFill
        superview.addSubview(snapshotView)

        snapshots[id] = snapshotView
        contentView.isHidden = true
    }

    private func removeSnapshot(for contentView: UIView, id: ObjectIdentifier) {
        guard let snapshot = snapshots[id] else { return }
        snapshot.removeFromSuperview()
        snapshots.removeValue(forKey: id)
        contentView.isHidden = false
        contentView.transform = .identity
        contentView.alpha = 1.0
    }
}
