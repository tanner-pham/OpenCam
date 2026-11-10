import Foundation

nonisolated enum CaptureStoreError: Error, CustomStringConvertible {
    case documentsMissing
    case cannotCreateDirectory(path: String, reason: String)
    case cannotReadDirectory(path: String, reason: String)

    var description: String {
        switch self {
        case .documentsMissing:
            "[CaptureStore:appDefault] Documents folder not found — {directory: documentDirectory}"
        case .cannotCreateDirectory(let path, let reason):
            "[CaptureStore:init] Cannot create the captures folder — {path: \(path), reason: \(reason)}"
        case .cannotReadDirectory(let path, let reason):
            "[CaptureStore:init] Cannot read the captures folder — {path: \(path), reason: \(reason)}"
        }
    }
}
