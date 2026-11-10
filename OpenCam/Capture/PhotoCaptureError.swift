import Foundation

nonisolated enum PhotoCaptureError: Error, CustomStringConvertible, Equatable {
    case rawNeedsUnitZoom(zoom: Double)
    case rawUnavailable
    case noPhotoData
    case writeFailed(path: String, reason: String)
    case captureFailed(reason: String)

    var description: String {
        switch self {
        case .rawNeedsUnitZoom(let zoom):
            "[PhotoCapturer:capture] Bayer RAW needs zoom 1.0 — {zoom: \(zoom)}"
        case .rawUnavailable:
            "[PhotoCapturer:capture] No Bayer RAW format offered — {output: photo}"
        case .noPhotoData:
            "[PhotoCaptureDelegate:didFinishProcessingPhoto] Photo has no file data — {output: photo}"
        case .writeFailed(let path, let reason):
            "[PhotoCaptureDelegate:didFinishProcessingPhoto] Cannot write the photo — {path: \(path), reason: \(reason)}"
        case .captureFailed(let reason):
            "[PhotoCapturer:capture] Capture failed — {reason: \(reason)}"
        }
    }
}
