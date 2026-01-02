import OpenGlass
import SwiftUI

struct ContentView: View {
    @State private var configuration: GlassConfiguration = {
        var config = GlassConfiguration()
        config.blurRadius = 1.0
        config.glassTintStrength = 0.0
        config.cornerRadius = 100.0
        return config
    }()

    @State private var showingConfiguration = false
    @State private var glassPosition: CGPoint?
    @State private var glassSize = CGSize(width: 200, height: 200)

    var body: some View {
        GeometryReader { geometry in
            let defaultPosition = CGPoint(
                x: geometry.size.width / 2,
                y: geometry.size.height / 2,
            )

            ZStack {
                CPUImage(name: "SampleBackground")
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .ignoresSafeArea()

                GlassView(
                    configuration: $configuration,
                    position: $glassPosition,
                    defaultPosition: defaultPosition,
                )
                .frame(width: glassSize.width, height: glassSize.height)
                .position(glassPosition ?? defaultPosition)

                VStack {
                    Spacer()
                    Button {
                        showingConfiguration = true
                    } label: {
                        HStack {
                            Image(systemName: "slider.horizontal.3")
                            Text("Configure")
                        }
                        .font(.headline)
                        .foregroundColor(.primary)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(.background))
                    }
                    .padding(.bottom, 100)
                }
            }
        }
        .ignoresSafeArea()
        .sheet(isPresented: $showingConfiguration) {
            ConfigurationView(configuration: $configuration, glassSize: $glassSize)
        }
    }
}

#Preview {
    ContentView()
}
