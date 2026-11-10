import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import OpenCam

enum TestFiles {
    /// A new empty folder under the temporary directory.
    static func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "OpenCamTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A solid Display P3 colour, `size` x `size` at the origin.
    static func patch(_ rgb: SIMD3<Float>, size: Int = 8) throws -> CIImage {
        guard let colour = CIColor(red: CGFloat(rgb.x), green: CGFloat(rgb.y), blue: CGFloat(rgb.z), colorSpace: LookRenderer.shared.displayP3) else {
            throw TestFileError.colourUnavailable
        }
        return CIImage(color: colour).cropped(to: CGRect(x: 0, y: 0, width: size, height: size))
    }

    static func writeJPEG(width: Int, height: Int, rgb: SIMD3<Float>, to url: URL) throws -> URL {
        try jpegData(width: width, height: height, rgb: rgb).write(to: url)
        return url
    }

    static func writeHEIC(width: Int, height: Int, rgb: SIMD3<Float>, to url: URL) throws -> URL {
        try encode(.heic, width: width, height: height, rgb: rgb).write(to: url)
        return url
    }

    static func jpegData(width: Int, height: Int, rgb: SIMD3<Float>) throws -> Data {
        try encode(.jpeg, width: width, height: height, rgb: rgb)
    }

    static func pngData(width: Int, height: Int, rgb: SIMD3<Float>) throws -> Data {
        try encode(.png, width: width, height: height, rgb: rgb)
    }

    static func tiffData(width: Int, height: Int, rgb: SIMD3<Float>) throws -> Data {
        try encode(.tiff, width: width, height: height, rgb: rgb)
    }

    /// A solid colour picture, 8 bits per channel, tagged Display P3.
    private static func encode(_ type: UTType, width: Int, height: Int, rgb: SIMD3<Float>) throws -> Data {
        let space = LookRenderer.shared.displayP3
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
              let colour = CGColor(colorSpace: space, components: [CGFloat(rgb.x), CGFloat(rgb.y), CGFloat(rgb.z), 1])
        else { throw TestFileError.bitmapUnavailable }
        context.setFillColor(colour)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else { throw TestFileError.bitmapUnavailable }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else {
            throw TestFileError.encoderUnavailable(type: type.identifier)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw TestFileError.encoderUnavailable(type: type.identifier) }
        return Data(data)
    }
}
