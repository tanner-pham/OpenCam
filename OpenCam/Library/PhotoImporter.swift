import CoreGraphics
import Foundation
import ImageIO
import OSLog
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Copies pictures chosen outside OpenCam into the Captures folder as new originals.
@MainActor enum PhotoImporter {
    private static let logger = Logger(subsystem: "local.opencam.app", category: "PhotoImporter")
    private static let rawType = UTType("com.adobe.raw-image")

    /// The file kind a type is stored as, or nil when OpenCam does not keep that type.
    static func fileKind(for type: UTType) -> CaptureFileKind? {
        if type.conforms(to: .heic) || type.conforms(to: .heif) { return .heic }
        if type.conforms(to: .jpeg) { return .jpg }
        if type.conforms(to: .png) { return .png }
        if let rawType, type.conforms(to: rawType) { return .dng }
        return nil
    }

    /// Each candidate is checked before anything is written: its type must be kept and its bytes must decode. Only then is a
    /// number reserved and the original bytes written whole (atomically), so a failure leaves no file and uses no number.
    static func importCandidates(_ candidates: [ImportCandidate], into captures: CaptureStore) -> ImportResult {
        var imported: [URL] = []
        var failed = 0
        for candidate in candidates {
            guard let kind = fileKind(for: candidate.contentType), decodes(candidate.data) else {
                logger.error("[PhotoImporter:importCandidates] Not imported — {type: \(candidate.contentType.identifier, privacy: .public)}")
                failed += 1
                continue
            }
            let url = captures.url(sequence: captures.reserveSequence(), kind: kind)
            do {
                try candidate.data.write(to: url, options: .atomic)
                imported.append(url)
            } catch {
                logger.error("[PhotoImporter:importCandidates] Write failed — {type: \(candidate.contentType.identifier, privacy: .public), reason: \(error.localizedDescription, privacy: .public)}")
                failed += 1
            }
        }
        return ImportResult(imported: imported, failed: failed)
    }

    /// The picked item's bytes and its first type, or nil when either is missing.
    static func candidate(from item: PhotosPickerItem) async -> ImportCandidate? {
        guard let type = item.supportedContentTypes.first else { return nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return nil }
            return ImportCandidate(data: data, contentType: type)
        } catch {
            logger.error("[PhotoImporter:candidate] Load failed — {type: \(type.identifier, privacy: .public), reason: \(error.localizedDescription, privacy: .public)}")
            return nil
        }
    }

    /// True when the system can open the bytes and make a 64 px thumbnail from them.
    private static func decodes(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 64]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) != nil
    }
}
