import Foundation
@testable import OpenCam

/// Stands in for `CameraSession`: configuring a lens in `failingLensIDs` throws, everything else is recorded.
/// `startRecording` runs `onStartRecording` before it returns (a test can deliver a result there), and `stopRecording`
/// answers `isClipInFlight`; no recording result is ever sent on its own.
actor FakeSessionConfigurator: SessionConfigurator {
    let failingLensIDs: Set<String>
    let isClipInFlight: Bool
    let onStartRecording: @Sendable (URL, VideoOption) async -> Void
    private(set) var applied: [SessionConfiguration] = []
    private(set) var isRunning = true
    private(set) var stopCount = 0
    private(set) var recordingURLs: [URL] = []
    private(set) var stopRecordingCount = 0

    init(failingLensIDs: Set<String>, isClipInFlight: Bool = false,
         onStartRecording: @escaping @Sendable (URL, VideoOption) async -> Void = { _, _ in }) {
        self.failingLensIDs = failingLensIDs
        self.isClipInFlight = isClipInFlight
        self.onStartRecording = onStartRecording
    }

    func configure(_ configuration: SessionConfiguration) throws(CameraSessionError) {
        guard !failingLensIDs.contains(configuration.lens.id) else {
            throw .noMatchingFormat(option: "fake \(configuration.lens.id)")
        }
        applied.append(configuration)
    }

    func start() { isRunning = true }

    func stop() {
        isRunning = false
        stopCount += 1
    }

    func startRecording(option: VideoOption, url: URL, minFreeBytes: Int64) async throws(RecordingError) {
        recordingURLs.append(url)
        await onStartRecording(url, option)
    }

    func stopRecording() -> Bool {
        stopRecordingCount += 1
        return isClipInFlight
    }
}
