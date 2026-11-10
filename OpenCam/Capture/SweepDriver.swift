import Foundation

/// What a format sweep asks of the camera, one step at a time. `CameraModel` is the real one, so every step goes through
/// the model's own configure queue and recording path; tests use a fake.
@MainActor protocol SweepDriver: AnyObject {
    /// False during an interruption or after the camera stopped; every clip would fail at once, which says nothing
    /// about the option, so the sweep ends and the rows recorded meanwhile are not answers.
    var isCameraUsable: Bool { get }
    /// Selects `option` and waits until the session has applied it; throws when it could not be used.
    func applySweepOption(_ option: VideoOption) async throws(CameraSessionError)
    /// Starts a clip of the applied option and returns once it is recording or has failed to start.
    /// True when a result will reach `FormatSweep.recordingDidFinish` (it may already have); false when none will.
    func beginSweepClip() async -> Bool
    /// Stops the clip; its result follows through `FormatSweep.recordingDidFinish`.
    func endSweepClip()
}
