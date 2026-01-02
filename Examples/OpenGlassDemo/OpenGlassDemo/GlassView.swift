import OpenGlass
import SwiftUI

struct GlassView: UIViewRepresentable {
    @Binding var configuration: GlassConfiguration
    @Binding var position: CGPoint?
    var defaultPosition: CGPoint

    func makeCoordinator() -> Coordinator {
        Coordinator(position: $position)
    }

    func makeUIView(context: Context) -> OpenGlassView {
        let view = OpenGlassView(configuration: configuration)
        view.onPositionChange = { newPosition in
            context.coordinator.position.wrappedValue = newPosition
        }
        return view
    }

    func updateUIView(_ view: OpenGlassView, context _: Context) {
        view.configuration = configuration
        view.currentPosition = position ?? defaultPosition
    }

    class Coordinator {
        var position: Binding<CGPoint?>

        init(position: Binding<CGPoint?>) {
            self.position = position
        }
    }
}
