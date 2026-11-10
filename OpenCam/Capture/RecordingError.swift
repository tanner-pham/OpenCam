import Foundation

nonisolated enum RecordingError: Error, CustomStringConvertible, Equatable {
    case sessionNotRunning
    case outputNotAttached
    case whiteBalanceNotSet(reason: String)
    case alreadyRecording
    case noVideoConnection
    case codecUnavailable(codec: String, available: [String])
    case cannotInspect(path: String, reason: String)
    case noVideoTrack(path: String)
    case cannotWriteSidecar(path: String, reason: String)

    var description: String {
        switch self {
        case .sessionNotRunning:
            "[CameraSession:startRecording] Session not running — {output: movie}"
        case .outputNotAttached:
            "[CameraSession:startRecording] Movie output not attached — {mode: video}"
        case .whiteBalanceNotSet(let reason):
            "[CameraSession:startRecording] Cannot set white balance — {reason: \(reason)}"
        case .alreadyRecording:
            "[MovieRecorder:start] Already recording — {output: movie}"
        case .noVideoConnection:
            "[MovieRecorder:start] Movie output has no active camera connection — {output: movie}"
        case .codecUnavailable(let codec, let available):
            "[MovieRecorder:start] Codec not offered — {codec: \(codec), available: \(available.joined(separator: ","))}"
        case .cannotInspect(let path, let reason):
            "[ClipInspector:inspect] Cannot read the clip — {path: \(path), reason: \(reason)}"
        case .noVideoTrack(let path):
            "[ClipInspector:inspect] Clip has no video track — {path: \(path)}"
        case .cannotWriteSidecar(let path, let reason):
            "[MovieRecorder:writeSidecar] Cannot write the sidecar — {path: \(path), reason: \(reason)}"
        }
    }
}
