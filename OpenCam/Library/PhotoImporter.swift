import CoreGraphics
import Foundation
import ImageIO
import OSLog
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Copies pictures chosen outside OpenCam into the Captures folder as new originals.
@MainActor enum PhotoImporter {
    private nonisolated static let logger = Logger(subsystem: "local.opencam.app", category: "PhotoImporter")
    private nonisolated static let rawType = UTType("com.adobe.raw-image")

    /// The file kind a type is stored as, or nil when OpenCam does not keep that type.
    nonisolated static func fileKind(for type: UTType) -> CaptureFileKind? {
        if type.conforms(to: .heic) || type.conforms(to: .heif) { return .heic }
        if type.conforms(to: .jpeg) { return .jpg }
        if type.conforms(to: .png) { return .png }
        if let rawType, type.conforms(to: rawType) { return .dng }
        return nil
    }

    /// Already loaded candidates, imported in order: `importEach` with nothing to load.
    static func importCandidates(_ candidates: [ImportCandidate], into captures: CaptureStore) async -> ImportResult {
        await importEach(candidates, into: captures) { $0 }
    }

    /// Loads, imports and releases one source at a time, so a batch never holds more than one picture's bytes (thirty ProRAW
    /// files would not fit in memory at once). A source that cannot be loaded counts as one that could not be imported.
    static func importEach<Source>(_ sources: [Source], into captures: CaptureStore,
                                   load: (Source) async -> ImportCandidate?) async -> ImportResult {
        var imported: [URL] = []
        var failed = 0
        for source in sources {
            guard let candidate = await load(source) else {
                failed += 1
                continue
            }
            if let url = await importCandidate(candidate, into: captures) { imported.append(url) } else { failed += 1 }
        }
        return ImportResult(imported: imported, failed: failed)
    }

    /// The candidate is proven first, off the main actor: its bytes must decode, and the kind kept comes from the bytes
    /// (the declared type is only a hint). Only then is a number reserved (here, on the main actor) and the bytes written off
    /// the main actor, to a temporary file moved into place without replacing anything. A failure leaves no file and, before
    /// the write, uses no number. Returns the new file, or nil.
    static func importCandidate(_ candidate: ImportCandidate, into captures: CaptureStore) async -> URL? {
        guard let kind = await provenKind(of: candidate) else {
            logger.error("[PhotoImporter:importCandidate] Not imported — {type: \(candidate.contentType.identifier, privacy: .public)}")
            return nil
        }
        let url = captures.url(sequence: captures.reserveSequence(), kind: kind)
        guard await write(candidate.data, to: url) else {
            logger.error("[PhotoImporter:importCandidate] Write failed — {type: \(candidate.contentType.identifier, privacy: .public)}")
            return nil
        }
        return url
    }

    /// The kind the bytes really are, or nil when the system cannot open them, make a 64 px thumbnail, or they are not a kept type.
    @concurrent private static func provenKind(of candidate: ImportCandidate) async -> CaptureFileKind? {
        guard let source = CGImageSourceCreateWithData(candidate.data as CFData, nil),
              let identifier = CGImageSourceGetType(source), let sniffed = UTType(identifier as String),
              let kind = fileKind(for: sniffed)
        else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 64]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) == nil ? nil : kind
    }

    /// Writes beside `url` under a temporary name, then moves it into place. `moveItem` fails when `url` exists, so an existing
    /// file is never replaced; on any failure the temporary file is removed.
    @concurrent private static func write(_ data: Data, to url: URL) async -> Bool {
        let temporary = url.deletingLastPathComponent().appending(path: ".import-\(UUID().uuidString).tmp", directoryHint: .notDirectory)
        do {
            try data.write(to: temporary)
            try FileManager.default.moveItem(at: temporary, to: url)
            return true
        } catch {
            logger.error("[PhotoImporter:write] \(error.localizedDescription, privacy: .public)")
            try? FileManager.default.removeItem(at: temporary)
            return false
        }
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
}
