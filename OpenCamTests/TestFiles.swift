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

    /// Every file name in `directory` with its content modification date, to show a folder was left unchanged.
    static func snapshot(_ directory: URL) throws -> [String: Date] {
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))
        var dates: [String: Date] = [:]
        for name in names {
            let url = directory.appending(path: name, directoryHint: .notDirectory)
            dates[name] = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
        }
        return dates
    }

    /// A picture of `type` whose stored pixels are red on the left half and blue on the right, tagged with EXIF `orientation`.
    /// Orientation 6 shows it turned a quarter clockwise: upright, red is the top half.
    static func writeOrientedPicture(width: Int, height: Int, orientation: Int, type: UTType, to url: URL) throws -> URL {
        let space = LookRenderer.shared.displayP3
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
              let red = CGColor(colorSpace: space, components: [1, 0, 0, 1]),
              let blue = CGColor(colorSpace: space, components: [0, 0, 1, 1])
        else { throw TestFileError.bitmapUnavailable }
        context.setFillColor(red)
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        context.setFillColor(blue)
        context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)
        else { throw TestFileError.encoderUnavailable(type: type.identifier) }
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw TestFileError.encoderUnavailable(type: type.identifier) }
        return url
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

    static func heicData(width: Int, height: Int, rgb: SIMD3<Float>) throws -> Data {
        try encode(.heic, width: width, height: height, rgb: rgb)
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
