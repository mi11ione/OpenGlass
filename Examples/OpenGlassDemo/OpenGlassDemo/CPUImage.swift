import SwiftUI
import UIKit

extension UIImage {
    func forceCPURendering() -> UIImage {
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        draw(in: CGRect(origin: .zero, size: size))
        let result = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return result ?? self
    }
}

struct CPUImage: View {
    let name: String

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
            } else {
                Color.clear
            }
        }
        .onAppear {
            if image == nil {
                DispatchQueue.global(qos: .userInitiated).async {
                    guard let original = UIImage(named: name) else { return }
                    let rendered = original.forceCPURendering()
                    DispatchQueue.main.async {
                        image = rendered
                    }
                }
            }
        }
    }
}
