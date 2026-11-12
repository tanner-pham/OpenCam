import Foundation

/// Why the session could not set the camera by hand.
nonisolated enum ManualControlError: Error, CustomStringConvertible, Equatable {
    case noCamera
    case lockFailed(reason: String)
    case notSupported(control: String, lens: String)

    var description: String {
        switch self {
        case .noCamera:
            "[CameraSession:applyManual] No running camera — {running: false}"
        case .lockFailed(let reason):
            "[CameraSession:applyManual] Cannot lock the camera for configuration — {reason: \(reason)}"
        case .notSupported(let control, let lens):
            "[CameraSession:applyManual] Control not supported by this camera — {control: \(control), lens: \(lens)}"
        }
    }
}
