import MetalKit

/// Captures screen content into Metal textures for glass effect rendering.
///
/// Renders a portion of a source view's layer into a CPU buffer, then uploads
/// to a reusable Metal texture. Optimizes memory usage by caching buffers and
/// textures, resizing only when needed.
///
/// Uses Core Graphics rendering with layer capture, which works without
/// private APIs and is App Store safe.
///
/// - Note: Internal class used by ``SharedGlassCapture``.
/// - SeeAlso: ``SharedGlassCapture``
@MainActor
final class GlassTextureCapture {
    private let device: MTLDevice

    private var cachedTexture: MTLTexture?
    private var cachedTextureWidth: Int = 0
    private var cachedTextureHeight: Int = 0

    private var renderBuffer: UnsafeMutablePointer<UInt8>?
    private var renderBufferCapacity: Int = 0

    private let colorSpace = CGColorSpaceCreateDeviceRGB()

    private enum Constants {
        static let bytesPerPixel: Int = 4
        static let bitmapInfo: UInt32 = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    }

    private let captureScale: CGFloat

    /// Creates a capture instance with the specified Metal device.
    ///
    /// - Parameter device: Metal device for texture creation.
    /// - Returns: Configured instance, or nil if device is nil.
    init?(device: MTLDevice?) {
        guard let device else { return nil }
        self.device = device
        captureScale = UIScreen.main.scale
    }

    /// Captures a rectangular region of a view into a Metal texture.
    ///
    /// Renders the source view's layer at screen scale, then uploads the pixels
    /// to a cached texture. Reuses texture if size matches previous capture.
    ///
    /// - Parameters:
    ///   - sourceView: View whose layer content to capture.
    ///   - rect: Rectangle in source view's coordinate space to capture.
    /// - Returns: Metal texture containing the captured content, or nil on failure.
    func capture(sourceView: UIView, rect: CGRect) -> MTLTexture? {
        let scale = captureScale
        let pixelWidth = Int(ceil(rect.width * scale))
        let pixelHeight = Int(ceil(rect.height * scale))

        guard pixelWidth > 0, pixelHeight > 0 else { return nil }

        let bytesPerRow = pixelWidth * Constants.bytesPerPixel
        let requiredBufferSize = pixelHeight * bytesPerRow

        ensureRenderBufferCapacity(requiredBufferSize)
        guard let buffer = renderBuffer else { return nil }

        ensureTextureSize(width: pixelWidth, height: pixelHeight)
        guard let texture = cachedTexture else { return nil }

        guard let context = CGContext(
            data: buffer,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: Constants.bitmapInfo,
        ) else { return nil }

        context.translateBy(x: 0, y: CGFloat(pixelHeight))
        context.scaleBy(x: scale, y: -scale)
        context.translateBy(x: -rect.origin.x, y: -rect.origin.y)

        sourceView.layer.render(in: context)

        texture.replace(
            region: MTLRegionMake2D(0, 0, pixelWidth, pixelHeight),
            mipmapLevel: 0,
            withBytes: buffer,
            bytesPerRow: bytesPerRow,
        )

        return texture
    }

    /// Releases all cached textures and buffers.
    ///
    /// Called by ``SharedGlassCapture`` when all glass views are removed.
    func releaseResources() {
        cachedTexture = nil
        cachedTextureWidth = 0
        cachedTextureHeight = 0
        renderBuffer?.deallocate()
        renderBuffer = nil
        renderBufferCapacity = 0
    }

    private func ensureRenderBufferCapacity(_ requiredSize: Int) {
        if renderBuffer == nil || renderBufferCapacity < requiredSize {
            renderBuffer?.deallocate()
            renderBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: requiredSize)
            renderBufferCapacity = requiredSize
        }
    }

    private func ensureTextureSize(width: Int, height: Int) {
        if cachedTexture != nil,
           cachedTextureWidth == width,
           cachedTextureHeight == height
        {
            return
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false,
        )
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared

        cachedTexture = device.makeTexture(descriptor: descriptor)
        cachedTextureWidth = width
        cachedTextureHeight = height
    }
}
