import Foundation

/// What the model needs from the session to apply a selection and record. `CameraSession` is the real one; tests use a fake.
nonisolated protocol SessionConfigurator: Sendable {
    /// Throws when the configuration cannot be applied; the session then keeps or restores the last one that worked.
    func configure(_ configuration: SessionConfiguration) async throws(CameraSessionError)
    func start() async
    /// A rescan stops the session first, because it sets each camera's format directly.
    func stop() async
    /// Starts recording `option`, which must already be configured, to `url`; the result arrives through the session's
    /// recordings once the clip ends.
    func startRecording(option: VideoOption, url: URL, minFreeBytes: Int64) async throws(RecordingError)
    /// Stops the clip. Returns whether a clip was in flight; false means no recording result will follow.
    func stopRecording() async -> Bool
}
