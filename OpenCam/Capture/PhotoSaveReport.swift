import Foundation

/// What the screen says about one photo press: a notice naming what was not saved, and the file to show as the last capture.
/// Error descriptions never reach the notice; the caller logs them.
nonisolated struct PhotoSaveReport: Equatable, Sendable {
    /// Nil when every requested file was saved.
    let notice: String?
    /// The HEIC if saved, else the DNG; nil when nothing was saved.
    let lastCapture: URL?

    static let photoNotSaved = "Photo not saved."
    static let rawNotSaved = "RAW not saved. HEIF saved."
    static let heifNotSaved = "HEIF not saved. RAW saved."
    static let notices: Set<String> = [photoNotSaved, rawNotSaved, heifNotSaved]

    /// An error reported after every requested file was saved does not change the outcome; the files are there.
    static func make(requested: [URL], saved: [URL], error: PhotoCaptureError?) -> PhotoSaveReport {
        let savedRAW = saved.first { isRAW($0) }
        let savedHEIF = saved.first { !isRAW($0) }
        let lastCapture = savedHEIF ?? savedRAW
        let missing = requested.filter { !saved.contains($0) }
        guard !missing.isEmpty else { return PhotoSaveReport(notice: nil, lastCapture: lastCapture) }
        guard !saved.isEmpty else { return PhotoSaveReport(notice: photoNotSaved, lastCapture: nil) }
        let notice = missing.contains(where: isRAW) ? rawNotSaved : heifNotSaved
        return PhotoSaveReport(notice: notice, lastCapture: lastCapture)
    }

    private static func isRAW(_ url: URL) -> Bool {
        url.pathExtension == CaptureFileKind.dng.rawValue
    }
}
