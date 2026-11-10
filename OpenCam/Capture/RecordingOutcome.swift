import AVFoundation

/// How one recording ended. A playable clip is always reported as saved; error descriptions never reach the notice.
nonisolated enum RecordingOutcome: Sendable, Equatable {
    case completed
    /// Ended by an error; `isPlayable` is the movie output's own verdict on the file.
    case stopped(StopReason, isPlayable: Bool)
    /// The recording could not start; carries a log message only.
    case failed(String)

    static let storageFullNotice = "Recording stopped. Storage is full. Clip saved."
    static let interruptedNotice = "Recording stopped. The camera was interrupted. Clip saved."
    static let failedNotice = "Recording failed. The clip could not be saved."
    /// A clip whose end the camera never reported but whose file is on disk: it is never called lost.
    static let incompleteNotice = "Recording stopped. The clip may be incomplete."

    /// AVError.h: `AVErrorRecordingSuccessfullyFinishedKey` says whether the file is playable despite the error.
    init(error: NSError?) {
        guard let error else {
            self = .completed
            return
        }
        let isPlayable = (error.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool) ?? false
        self = .stopped(Self.reason(error), isPlayable: isPlayable)
    }

    var isPlayable: Bool {
        switch self {
        case .completed: true
        case .stopped(_, let isPlayable): isPlayable
        case .failed: false
        }
    }

    /// Nil when the clip saved with nothing to report.
    var notice: String? {
        switch self {
        case .completed: nil
        case .stopped(.noResult, _): Self.incompleteNotice
        case .stopped(_, false), .failed: Self.failedNotice
        case .stopped(.storageFull, true): Self.storageFullNotice
        case .stopped(.interrupted, true): Self.interruptedNotice
        case .stopped(.maximumFileSize, true), .stopped(.maximumDuration, true), .stopped(.other, true): nil
        }
    }

    /// For the sidecar.
    var summary: String {
        switch self {
        case .completed: "completed"
        case .stopped(let reason, let isPlayable): "stopped: \(reason), \(isPlayable ? "playable" : "not playable")"
        case .failed: "failed"
        }
    }

    /// Nil at 0; otherwise "OC_0002 dropped 1 frame." or "OC_0002 dropped 5 frames.".
    static func droppedFramesNotice(clipName: String, droppedFrames: Int) -> String? {
        switch droppedFrames {
        case ...0: nil
        case 1: "\(clipName) dropped 1 frame."
        default: "\(clipName) dropped \(droppedFrames) frames."
        }
    }

    private static func reason(_ error: NSError) -> StopReason {
        guard error.domain == AVFoundationErrorDomain else { return .other(code: error.code) }
        switch AVError.Code(rawValue: error.code) {
        case .diskFull: return .storageFull
        case .sessionWasInterrupted: return .interrupted
        case .maximumFileSizeReached: return .maximumFileSize
        case .maximumDurationReached: return .maximumDuration
        default: return .other(code: error.code)
        }
    }
}
