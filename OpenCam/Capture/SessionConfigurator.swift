import Foundation

/// What the model needs from the session to apply a selection and record. `CameraSession` is the real one; tests use a fake.
nonisolated protocol SessionConfigurator: Sendable {
    /// Throws when the configuration cannot be applied; the session then keeps or restores the last one that worked.
    func configure(_ configuration: SessionConfiguration) async throws(CameraSessionError)
    func start() async
    /// Stops the session and detaches its camera, so a rescan can add each camera to a session of its own;
    /// the next `configure` attaches the camera again.
    func releaseCameras() async
    /// `releaseCameras()` for a session started from a saved start that the model does not keep; the session then marks the
    /// end of that start's events in its stream with `SessionEvent.savedStartReleased`.
    func releaseSavedStart() async
    /// Starts recording `option`, which must already be configured, to `url`; the result arrives through the session's
    /// recordings once the clip ends.
    /// `dropPolicy` applies on the writer path only. `stopRecording()` is true while a clip records or is being finished on either path.
    func startRecording(option: VideoOption, url: URL, minFreeBytes: Int64, dropPolicy: DropPolicy) async throws(RecordingError)
    /// Stops the clip. Returns whether a clip was in flight; false means no recording result will follow.
    func stopRecording() async -> Bool
    /// What the current camera reports now; empty while the session is stopped or holds no camera.
    func currentReadouts() async -> LiveReadouts
    /// What the current camera and its active format allow by hand; nil while the session is stopped or holds no camera.
    func manualRanges() async -> ManualRanges?
    /// Sets the camera to `settings`, changing only the groups that differ from the last settings applied to this camera;
    /// `reapplyingAll` sets every group. Never reconfigures the session; works while recording. Every value is clamped to
    /// the device's limits first, and the settings actually set are returned. A configure returns the camera to automatic.
    func applyManual(_ settings: ManualSettings, reapplyingAll: Bool) async throws(ManualControlError) -> ManualSettings
}
