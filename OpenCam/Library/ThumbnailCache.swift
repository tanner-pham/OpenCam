import AVFoundation
import CoreImage
import CryptoKit
import Foundation
import ImageIO
import OSLog
import UniformTypeIdentifiers

/// Small pictures of the library items, rendered with each photo's edit and kept as JPEG files named by `key`.
nonisolated struct ThumbnailCache: Sendable {
    static let longSide = 360
    private static let logger = Logger(subsystem: "local.opencam.app", category: "ThumbnailCache")

    let directory: URL

    /// `Library/Caches/Thumbnails`; created when the first thumbnail is written.
    static func appDefault() -> ThumbnailCache {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return ThumbnailCache(directory: caches.appending(path: "Thumbnails", directoryHint: .isDirectory))
    }

    init(directory: URL) {
        self.directory = directory
    }

    /// "<file name>-<milliseconds since 1970>-<first 16 hex of SHA-256 of the adjustments>.jpg"
    static func key(fileName: String, modified: Date, edit: PhotoEdit) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = (try? encoder.encode(edit.adjustments)) ?? Data()
        let digest = SHA256.hash(data: json).prefix(8).map { String(format: "%02x", $0) }.joined()
        return "\(fileName)-\(Int64((modified.timeIntervalSince1970 * 1000).rounded()))-\(digest).jpg"
    }

    /// Photo: the cached file, else a proxy of `Self.longSide` rendered through `LookRenderer`. Clip: the first frame, upright,
    /// with the edit ignored. Both are written as Display P3 JPEG.
    @concurrent func thumbnail(for item: LibraryItem, edit: PhotoEdit) async throws(PictureError) -> CGImage {
        let path = item.pictureURL.path(percentEncoded: false)
        let url = directory.appending(path: Self.key(fileName: item.pictureURL.lastPathComponent, modified: item.modified, edit: edit), directoryHint: .notDirectory)
        if let cached = Self.readCached(url) { return cached }

        let image: CGImage
        switch item.kind {
        case .photo:
            let proxy = try await PictureDecoder.proxy(at: item.pictureURL, longSide: Self.longSide)
            guard let rendered = await LookRenderer.shared.renderedCGImage(proxy, adjustments: edit.adjustments) else {
                throw .undecodable(path: path, in: .proxy)
            }
            image = rendered
        case .clip:
            image = try await Self.firstFrame(of: item.pictureURL)
        }
        write(image, to: url)
        return image
    }

    private static func readCached(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    @concurrent private static func firstFrame(of url: URL) async throws(PictureError) -> CGImage {
        let path = url.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else { throw .missing(path: path, in: .proxy) }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: longSide, height: longSide)
        let frame: CGImage
        do {
            frame = try await generator.image(at: .zero).image
        } catch {
            logger.error("[ThumbnailCache:firstFrame] Cannot read a frame — {path: \(path, privacy: .public), reason: \(error.localizedDescription, privacy: .public)}")
            throw .undecodable(path: path, in: .proxy)
        }
        guard let converted = await LookRenderer.shared.cgImage(CIImage(cgImage: frame)) else { throw .undecodable(path: path, in: .proxy) }
        return converted
    }

    /// A thumbnail that cannot be kept is still returned; the next request renders it again.
    private func write(_ image: CGImage, to url: URL) {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try (data as Data).write(to: url, options: .atomic)
        } catch {
            Self.logger.error("[ThumbnailCache:write] Cannot keep the thumbnail — {path: \(url.path(percentEncoded: false), privacy: .public), reason: \(error.localizedDescription, privacy: .public)}")
        }
    }
}
