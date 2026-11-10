import Foundation

nonisolated enum CameraSessionError: Error, CustomStringConvertible {
    case deviceMissing(lensID: String)
    case cannotAddInput(lensID: String)
    case cannotAddOutput(name: String)
    case noMatchingFormat(option: String)
    case lockFailed(reason: String)
    case recordingInProgress

    var description: String {
        switch self {
        case .deviceMissing(let lensID):
            "[CameraSession:configure] Camera not found — {lens: \(lensID)}"
        case .cannotAddInput(let lensID):
            "[CameraSession:configure] Cannot add input — {lens: \(lensID)}"
        case .cannotAddOutput(let name):
            "[CameraSession:configure] Cannot add output — {output: \(name)}"
        case .noMatchingFormat(let option):
            "[CameraSession:configure] No format matches — {option: \(option)}"
        case .lockFailed(let reason):
            "[CameraSession:configure] Cannot lock the camera for configuration — {reason: \(reason)}"
        case .recordingInProgress:
            "[CameraSession:configure] Cannot reconfigure while recording — {output: movie}"
        }
    }
}
