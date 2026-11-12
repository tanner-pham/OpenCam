import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

@MainActor extension SampleSeeder {
    /// The Simulator cannot write a real DNG (ImageIO lists no DNG destination type), so a RAW sample holds these bytes.
    private static let placeholderDNG = Data("OpenCam sample placeholder".utf8)

    /// 0 when Captures holds any DNG. Else, in order: a scene JPG (no Exif), a placeholder DNG alone, a scene HEIC with the
    /// sample Exif, and a scene HEIC with the sample Exif plus a placeholder DNG of the same number (the newest item).
    static func seedFormatsIfAbsent(_ captures: CaptureStore) throws(LibraryError) -> Int {
        guard !LibraryScanner.items(in: captures.directory).contains(where: { $0.rawURL != nil }) else { return 0 }
        let function = "seedFormatsIfAbsent"
        let scene = try renderedScene(function: function, path: captures.directory.path(percentEncoded: false))
        try writeJPEG(scene, to: captures.url(sequence: captures.reserveSequence(), kind: .jpg), function: function)
        try writePlaceholder(to: captures.url(sequence: captures.reserveSequence(), kind: .dng), function: function)
        try writeSampleHEIC(scene, to: captures.url(sequence: captures.reserveSequence(), kind: .heic), function: function)
        let sequence = captures.reserveSequence()
        try writeSampleHEIC(scene, to: captures.url(sequence: sequence, kind: .heic), function: function)
        try writePlaceholder(to: captures.url(sequence: sequence, kind: .dng), function: function)
        return 4
    }

    private static func renderedScene(function: String, path: String) throws(LibraryError) -> CGImage {
        let renderer = ImageRenderer(content: ViewfinderStandIn(showsCaption: false).frame(width: size.width, height: size.height))
        renderer.scale = scale
        guard let image = renderer.cgImage else { throw .seedFailed(function: function, path: path, reason: "The picture could not be rendered") }
        return image
    }

    private static func writeJPEG(_ image: CGImage, to url: URL, function: String) throws(LibraryError) {
        try encode(image, as: .jpeg, properties: [:] as CFDictionary, to: url, function: function)
    }

    private static func writeSampleHEIC(_ image: CGImage, to url: URL, function: String) throws(LibraryError) {
        // The sample Exif: lens, focal lengths, aperture, shutter and ISO.
        let exif: [CFString: Any] = [kCGImagePropertyExifLensModel: "Sample lens 6.9mm f/1.8", kCGImagePropertyExifFocalLength: 6.9,
                                     kCGImagePropertyExifFocalLenIn35mmFilm: 24, kCGImagePropertyExifFNumber: 1.8,
                                     kCGImagePropertyExifExposureTime: 1.0 / 120, kCGImagePropertyExifISOSpeedRatings: [100]]
        try encode(image, as: .heic, properties: [kCGImagePropertyExifDictionary: exif] as CFDictionary, to: url, function: function)
    }

    private static func encode(_ image: CGImage, as type: UTType, properties: CFDictionary, to url: URL, function: String) throws(LibraryError) {
        let path = url.path(percentEncoded: false)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw .seedFailed(function: function, path: path, reason: "No encoder for \(type.identifier)")
        }
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else {
            throw .seedFailed(function: function, path: path, reason: "The picture could not be encoded")
        }
    }

    private static func writePlaceholder(to url: URL, function: String) throws(LibraryError) {
        do {
            try placeholderDNG.write(to: url, options: .atomic)
        } catch {
            throw .seedFailed(function: function, path: url.path(percentEncoded: false), reason: error.localizedDescription)
        }
    }
}
