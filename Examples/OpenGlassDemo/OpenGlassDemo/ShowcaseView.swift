import OpenGlass
import SwiftUI

struct ShowcaseView: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                CPUImage(name: "SampleBackground")
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()

                VStack(alignment: .leading, spacing: 30) {
                    basicEffectsSection
                    buttonStylesSection
                    shapesSection
                    cornerRadiiSection
                    tintedGlassSection
                }
            }
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        Text("Showcase")
            .font(.largeTitle.bold())
            .padding(.horizontal, 32)
            .padding(.vertical, 16)
            .openGlassEffect(.regular.tint(.blue, mode: .multiply))
    }

    private var basicEffectsSection: some View {
        VStack(alignment: .leading) {
            Text(".glassEffect")
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(.background).opacity(0.8))

            HStack(spacing: 16) {
                label("Regular")
                    .openGlassEffect(.regular)

                label("Clear")
                    .openGlassEffect(.clear)
            }
        }
    }

    private var buttonStylesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(".buttonStyle")
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(.background).opacity(0.8))

            HStack(spacing: 16) {
                Button {} label: {
                    Text("Default")
                        .foregroundColor(.white)
                }
                .buttonStyle(.openGlass)

                Button {} label: {
                    Text("Clear")
                        .foregroundColor(.white)
                }
                .buttonStyle(.openGlass(.clear))

                Button {} label: {
                    Text("Prominent")
                        .foregroundColor(.white)
                }
                    .buttonStyle(.openGlassProminent)
            }
        }
    }

    private var shapesSection: some View {
        VStack(alignment: .leading) {
            Text("shapes")
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(.background).opacity(0.8))

            HStack(spacing: 24) {
                icon("star.fill")
                    .openGlassEffect(in: Circle())

                icon("heart.fill")
                    .openGlassEffect(in: RoundedRectangle(cornerRadius: 16))

                icon("bolt.fill")
                    .frame(width: 64)
                    .openGlassEffect(in: Capsule())
            }
        }
    }

    private var cornerRadiiSection: some View {
        VStack(alignment: .leading) {
            Text("corner radii")
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(.background).opacity(0.8))

            HStack(spacing: 16) {
                Text("Diagonal")
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .frame(width: 80, height: 80)
                    .openGlassEffect(openCornerConfiguration: .corners(
                        topLeading: .fixed(32),
                        topTrailing: .fixed(8),
                        bottomLeading: .fixed(8),
                        bottomTrailing: .fixed(32),
                    ))

                Text("Top")
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .frame(width: 80, height: 80)
                    .openGlassEffect(openCornerConfiguration: .corners(
                        topLeading: .fixed(32),
                        topTrailing: .fixed(32),
                        bottomLeading: .fixed(4),
                        bottomTrailing: .fixed(4),
                    ))

                Text("Bottom")
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .frame(width: 80, height: 80)
                    .openGlassEffect(openCornerConfiguration: .corners(
                        topLeading: .fixed(4),
                        topTrailing: .fixed(4),
                        bottomLeading: .fixed(32),
                        bottomTrailing: .fixed(32),
                    ))
            }
        }
    }

    private var tintedGlassSection: some View {
        VStack(alignment: .leading) {
            Text("tint")
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(.background).opacity(0.8))

            VStack(alignment: .leading) {
                HStack(spacing: 12) {
                    tintedChip(".colorDodge", .red, .colorDodge)
                    tintedChip(".multiply", .red, .multiply)
                    tintedChip(".overlay", .red, .overlay)
                }
                HStack(spacing: 12) {
                    tintedChip(".screen", .red, .screen)
                    tintedChip(".softLight", .red, .softLight)
                }
            }
        }
    }

    private func tintedChip(_ text: String, _ color: Color, _ mode: OpenGlassTintMode) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .openGlassEffect(.regular.tint(color, mode: mode))
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.body)
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
    }

    private func icon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.title2)
            .foregroundColor(.white)
            .frame(width: 56, height: 56)
    }
}

#Preview {
    ShowcaseView()
}
