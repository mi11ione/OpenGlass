import OpenGlass
import SwiftUI

struct ContainerView: View {
    @State private var stackSpacing: CGFloat = -4
    @State private var containerSpacing: CGFloat = 16

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                CPUImage(name: "SampleBackground")
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()

                VStack {
                    VStack(spacing: -80) {
                        horizontalExample

                        verticalExample

                        gridExample
                    }

                    controlsPanel
                }
                .offset(y: -50)
            }
        }
        .ignoresSafeArea()
    }

    private var horizontalExample: some View {
        OpenGlassEffectContainer(spacing: containerSpacing) {
            HStack(spacing: stackSpacing) {
                ForEach(["A", "B", "C", "D"], id: \.self) { letter in
                    Text(letter)
                        .font(.title3.bold())
                        .foregroundColor(.white)
                        .frame(width: 70, height: 60)
                        .openGlassEffect()
                }
            }
        }
    }

    private var verticalExample: some View {
        OpenGlassEffectContainer(spacing: containerSpacing) {
            VStack(spacing: stackSpacing) {
                ForEach(["Row 1", "Row 2", "Row 3"], id: \.self) { text in
                    Text(text)
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                        .frame(width: 200, height: 44)
                        .openGlassEffect()
                }
            }
        }
    }

    private var gridExample: some View {
        OpenGlassEffectContainer(spacing: containerSpacing) {
            VStack(spacing: stackSpacing) {
                HStack(spacing: stackSpacing) {
                    gridCell("1")
                    gridCell("2")
                    gridCell("3")
                }
                HStack(spacing: stackSpacing) {
                    gridCell("4")
                    gridCell("5")
                    gridCell("6")
                }
            }
        }
    }

    private func gridCell(_ text: String) -> some View {
        Text(text)
            .font(.title2.bold())
            .foregroundColor(.white)
            .frame(width: 80, height: 80)
            .openGlassEffect()
    }

    private var controlsPanel: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Stack Spacing")
                    .foregroundColor(.white)
                Spacer()
                Text("\(Int(stackSpacing))")
                    .foregroundColor(.white.opacity(0.7))
            }
            Slider(value: $stackSpacing, in: -20 ... 20)

            HStack {
                Text("Container Spacing")
                    .foregroundColor(.white)
                Spacer()
                Text("\(Int(containerSpacing))")
                    .foregroundColor(.white.opacity(0.7))
            }
            Slider(value: $containerSpacing, in: 0 ... 40)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.black.opacity(0.5)))
        .padding()
        .padding(.bottom, 24)
    }
}

#Preview {
    ContainerView()
}
