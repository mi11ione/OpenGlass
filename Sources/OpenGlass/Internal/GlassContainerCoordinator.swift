import UIKit

/// Coordinates child registrations between SwiftUI and the container renderer.
///
/// `GlassContainerCoordinator` bridges SwiftUI's declarative child views with the
/// imperative UIKit container. It tracks child registrations, syncs frame updates,
/// and forwards configuration changes.
///
/// Created by ``OpenGlassEffectContainer`` and stored in its SwiftUI coordinator.
///
/// - SeeAlso: ``OpenGlassEffectContainer``, ``OpenGlassContainerRenderView``
@MainActor
public final class GlassContainerCoordinator {
    /// Registration data for a single child element.
    public struct ChildRegistration {
        /// Unique identifier for this child.
        public let id: ObjectIdentifier
        /// The child's UIView (weak reference).
        public weak var view: UIView?
        /// Content view to hide during capture (weak reference).
        public weak var contentView: UIView?
        /// Glass style and configuration builder.
        public var glass: OpenGlass
        /// Corner radius configuration.
        public var openCornerConfiguration: OpenGlassCornerConfiguration
        /// Cached frame in container coordinates.
        public var frame: CGRect

        public init(
            id: ObjectIdentifier,
            view: UIView?,
            contentView: UIView?,
            glass: OpenGlass,
            openCornerConfiguration: OpenGlassCornerConfiguration,
            frame: CGRect,
        ) {
            self.id = id
            self.view = view
            self.contentView = contentView
            self.glass = glass
            self.openCornerConfiguration = openCornerConfiguration
            self.frame = frame
        }
    }

    private var registrations: [ObjectIdentifier: ChildRegistration] = [:]
    /// The container render view this coordinator manages.
    weak var containerView: OpenGlassContainerRenderView?

    public init() {}

    /// Registers a child element with the container.
    ///
    /// Creates a registration, notifies and syncs to the container render view.
    /// Called by SwiftUI child views on appear.
    public func register(
        id: ObjectIdentifier,
        view: UIView,
        contentView: UIView?,
        glass: OpenGlass,
        openCornerConfiguration: OpenGlassCornerConfiguration,
    ) {
        let registration = ChildRegistration(
            id: id,
            view: view,
            contentView: contentView,
            glass: glass,
            openCornerConfiguration: openCornerConfiguration,
            frame: view.frame,
        )
        registrations[id] = registration

        SharedGlassCapture.shared.registerContainerChild(
            id: id,
            coordinator: self,
            config: glass.makeConfiguration(),
        )

        syncToContainer()
    }

    /// Unregisters a child element from the container.
    ///
    /// Called by SwiftUI child views on disappear.
    public func unregister(id: ObjectIdentifier) {
        registrations.removeValue(forKey: id)
        SharedGlassCapture.shared.unregisterContainerChild(id: id)
        syncToContainer()
    }

    /// Updates a child's frame after layout changes.
    public func updateFrame(id: ObjectIdentifier, frame: CGRect) {
        guard var reg = registrations[id] else { return }
        reg.frame = frame
        registrations[id] = reg
        syncToContainer()
    }

    /// Updates a child's corner radius configuration.
    public func updateCornerRadii(id: ObjectIdentifier, openCornerConfiguration: OpenGlassCornerConfiguration) {
        guard var reg = registrations[id] else { return }
        reg.openCornerConfiguration = openCornerConfiguration
        registrations[id] = reg
        syncToContainer()
    }

    /// Updates a child's glass style and tint configuration.
    public func updateGlass(id: ObjectIdentifier, glass: OpenGlass) {
        guard var reg = registrations[id] else { return }
        reg.glass = glass
        registrations[id] = reg

        SharedGlassCapture.shared.updateContainerChildConfig(
            id: id,
            config: glass.makeConfiguration(),
        )

        syncToContainer()
    }

    private func syncToContainer() {
        guard let container = containerView else { return }

        registrations = registrations.filter { $0.value.view != nil }

        for (id, reg) in registrations {
            guard let view = reg.view else { continue }

            let frameInContainer = view.convert(view.bounds, to: container)
            let resolved = reg.openCornerConfiguration.resolve(size: frameInContainer.size)

            let config = reg.glass.makeConfiguration()

            container.registerChild(
                id: id,
                view: view,
                contentView: reg.contentView,
                cornerRadii: resolved,
                tintColor: config.tintColor,
                tintMode: config.tintMode,
                tintIntensity: config.tintIntensity,
            )

            container.updateChildFrame(id: id, frame: frameInContainer)
        }
    }

    /// Returns all current child registrations.
    public func getRegistrations() -> [ChildRegistration] {
        Array(registrations.values)
    }

    /// Returns the content view for a child (used for transform application).
    public func getChildContentView(id: ObjectIdentifier) -> UIView? {
        registrations[id]?.contentView
    }
}
