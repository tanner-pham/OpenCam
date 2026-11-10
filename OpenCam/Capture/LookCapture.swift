import Foundation
import OSLog

/// Applies the selected look to a photo the camera has already written. The camera's file is on disk the whole time, so a
/// failure at any step leaves the photo as captured.
nonisolated enum LookCapture {
    static let lookNotApplied = "Look not applied. The photo was saved without it."
    static let lookNotSaved = "Look not saved with the photo."
    private static let logger = Logger(subsystem: "local.opencam.app", category: "LookCapture")

    /// HEIF in `result.saved` is baked in place by one atomic write. A RAW-only capture gets an edit file beside the
    /// untouched DNG. `result` comes back unchanged; only the notice differs.
    @concurrent static func finish(_ result: PhotoCaptureResult, look: CameraLook, format: PhotoFormat, heicURL: URL, dngURL: URL,
                                   edits: EditStore, renderer: LookRenderer = .shared) async -> LookCaptureOutcome {
        switch format {
        case .heif, .rawPlusHEIF:
            guard result.saved.contains(heicURL) else { return LookCaptureOutcome(result: result, notice: nil) }
            let isBaked = bake(heicURL, look: look, renderer: renderer)
            return LookCaptureOutcome(result: result, notice: isBaked ? nil : lookNotApplied)
        case .raw:
            guard result.saved.contains(dngURL) else { return LookCaptureOutcome(result: result, notice: nil) }
            let stem = dngURL.deletingPathExtension().lastPathComponent
            do {
                try edits.save(PhotoEdit(adjustments: look.adjustments, lookName: look.name), stem: stem)
                return LookCaptureOutcome(result: result, notice: nil)
            } catch {
                logger.error("\(error.description, privacy: .public)")
                return LookCaptureOutcome(result: result, notice: lookNotSaved)
            }
        }
    }

    /// The baked bytes are dropped as soon as the write returns.
    private static func bake(_ url: URL, look: CameraLook, renderer: LookRenderer) -> Bool {
        let path = url.path(percentEncoded: false)
        do {
            let source = try Data(contentsOf: url)
            let baked: Data
            do {
                baked = try LookBaker.bake(source, adjustments: look.adjustments, renderer: renderer)
            } catch {
                logger.error("\(error.description, privacy: .public) — {path: \(path, privacy: .public), bytes: \(source.count)}")
                return false
            }
            try baked.write(to: url, options: .atomic)
            return true
        } catch {
            logger.error("[LookCapture:bake] The photo could not be read or replaced — {path: \(path, privacy: .public), reason: \(error.localizedDescription, privacy: .public)}")
            return false
        }
    }
}
