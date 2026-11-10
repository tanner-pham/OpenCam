import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Decodes HEIC, HEIF, JPEG, PNG and DNG pictures, upright. A DNG gets the system's default RAW decode.
nonisolated enum PictureDecoder {
    /// The whole picture at full size.
    static func full(at url: URL) throws(PictureError) -> CIImage {
        try requireFile(url)
        let image: CIImage?
        if isRAW(url) {
            image = CIRAWFilter(imageURL: url)?.outputImage
        } else {
            image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true])
        }
        guard let image else { throw .undecodable(path: url.path(percentEncoded: false)) }
        return image
    }

    /// A decoded copy whose long side is at most `longSide`, never upscaled. Rendered once, so later renders never decode again.
    @concurrent static func proxy(at url: URL, longSide: Int) async throws(PictureError) -> CIImage {
        try requireFile(url)
        let cgImage = isRAW(url) ? await rawProxy(at: url, longSide: longSide) : thumbnail(at: url, longSide: longSide)
        guard let cgImage else { throw .undecodable(path: url.path(percentEncoded: false)) }
        return CIImage(cgImage: cgImage)
    }

    /// The upright pixel size, read from the file's properties without decoding it.
    static func pixelSize(at url: URL) throws(PictureError) -> CGSize {
        try requireFile(url)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { throw .undecodable(path: url.path(percentEncoded: false)) }
        // EXIF orientations 5 to 8 turn the picture a quarter, so width and height swap.
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        return (5...8).contains(orientation) ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
    }

    private static func requireFile(_ url: URL) throws(PictureError) {
        let path = url.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else { throw .missing(path: path) }
    }

    private static func isRAW(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .rawImage) ?? false
    }

    private static func thumbnail(at url: URL, longSide: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: longSide,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func rawProxy(at url: URL, longSide: Int) async -> CGImage? {
        guard let filter = CIRAWFilter(imageURL: url) else { return nil }
        let native = filter.nativeSize
        let nativeLongSide = max(native.width, native.height)
        if nativeLongSide > 0 {
            filter.scaleFactor = Float(min(1, CGFloat(longSide) / nativeLongSide))
        }
        guard let output = filter.outputImage else { return nil }
        return await LookRenderer.shared.cgImage(output)
    }
}
