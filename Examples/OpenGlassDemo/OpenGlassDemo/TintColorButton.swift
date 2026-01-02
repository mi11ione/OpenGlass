import OpenGlass
import SwiftUI

struct TintColorButton: View {
    let name: String
    let color: GlassTintColor?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    if let color {
                        Circle()
                            .fill(Color(
                                red: Double(color.red),
                                green: Double(color.green),
                                blue: Double(color.blue),
                            ))
                            .frame(width: 32, height: 32)
                    } else {
                        Circle()
                            .strokeBorder(Color.secondary, lineWidth: 2)
                            .frame(width: 32, height: 32)
                        Image(systemName: "xmark")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if isSelected {
                        Circle()
                            .strokeBorder(Color.primary, lineWidth: 3)
                            .frame(width: 38, height: 38)
                    }
                }
                .frame(width: 40, height: 40)

                Text(name)
                    .font(.caption2)
                    .foregroundColor(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}
