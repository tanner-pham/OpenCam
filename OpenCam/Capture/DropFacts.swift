import Foundation

/// What one writer clip counted, for the live count and the sidecar.
nonisolated struct DropFacts: Codable, Sendable, Equatable {
    var total = 0
    /// Keyed by `DropReason.rawValue`.
    var byReason: [String: Int] = [:]
    var framesDelivered = 0
    var framesWritten = 0
    var audioBuffersNotWritten = 0
    /// True when "Stop recording" ended the clip at a drop.
    var stoppedRecording = false
}
