import Foundation

/// Failures the sweep itself records in a row's `detail`, or logs.
nonisolated enum SweepError: Error, CustomStringConvertible {
    case cameraGone(lensID: String)
    case recordingDidNotStart(codec: String)
    case clipUnreadable(file: String)
    case stoppedEarly(file: String, outcome: String)
    case reportUnwritable(path: String, reason: String)
    case clipNotDeleted(path: String, reason: String)
    case deadlinePassed(step: String, codec: String)

    var description: String {
        switch self {
        case .cameraGone(let lensID):
            "[FormatSweep:run] The camera is no longer available — {lens: \(lensID)}"
        case .recordingDidNotStart(let codec):
            "[FormatSweep:run] Recording did not start — {codec: \(codec)}"
        case .clipUnreadable(let file):
            "[FormatSweep:run] Clip could not be read back — {file: \(file)}"
        case .stoppedEarly(let file, let outcome):
            "[FormatSweep:run] Recording ended early — {file: \(file), outcome: \(outcome)}"
        case .reportUnwritable(let path, let reason):
            "[FormatSweep:writeReport] Cannot write the report — {path: \(path), reason: \(reason)}"
        case .clipNotDeleted(let path, let reason):
            "[FormatSweep:removeClip] Cannot delete the clip — {path: \(path), reason: \(reason)}"
        case .deadlinePassed(let step, let codec):
            "[FormatSweep:run] No answer before the deadline — {step: \(step), codec: \(codec)}"
        }
    }
}
