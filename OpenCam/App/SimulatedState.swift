import Foundation

/// Honoured only in the Simulator.
nonisolated enum SimulatedState: String, Sendable { case scanning, cameraDenied, micDenied, lowStorage, storageFull, pressure, cameraStopped, cameraRestricted, sweepWarning }

/// Stands in for a session in the simulated stopped camera, so the model counts it as attached and offers Try again.
/// It records nothing.
nonisolated struct StoppedSessionStandIn: SessionConfigurator {
    func configure(_ configuration: SessionConfiguration) async throws(CameraSessionError) {}
    func start() async {}
    func releaseCameras() async {}
    func releaseSavedStart() async {}
    func startRecording(option: VideoOption, url: URL, minFreeBytes: Int64) async throws(RecordingError) { throw .sessionNotRunning }
    func stopRecording() async -> Bool { false }
    func currentReadouts() async -> LiveReadouts { LiveReadouts() }
    func manualRanges() async -> ManualRanges? { nil }
    func applyManual(_ settings: ManualSettings, reapplyingAll: Bool) async throws(ManualControlError) -> ManualSettings { settings }
}
