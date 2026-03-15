import SwiftUI

public struct OpenGlassButtonStyle: ButtonStyle {
    let glass: OpenGlass

    public init() {
        glass = .regular
    }

    public init(_ glass: OpenGlass) {
        self.glass = glass
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .openGlassEffect(glass.press())
    }
}

public extension ButtonStyle where Self == OpenGlassButtonStyle {
    static var openGlass: OpenGlassButtonStyle {
        OpenGlassButtonStyle()
    }

    static func openGlass(_ glass: OpenGlass) -> OpenGlassButtonStyle {
        OpenGlassButtonStyle(glass)
    }
}
