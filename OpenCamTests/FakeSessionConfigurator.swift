import Foundation
@testable import OpenCam

/// Stands in for `CameraSession`: configuring a lens in `failingLensIDs` throws, everything else is recorded.
/// `startRecording` runs `onStartRecording` before it returns (a test can deliver a result there), and `stopRecording`
/// answers `isClipInFlight`; no recording result is ever sent on its own.
actor FakeSessionConfigurator: SessionConfigurator {
    private(set) var failingLensIDs: Set<String>
    let isClipInFlight: Bool
    let onStartRecording: @Sendable (URL, VideoOption) async -> Void
    private(set) var applied: [SessionConfiguration] = []
    private(set) var isRunning = true
    private(set) var releaseCount = 0
    /// True while a camera input is attached: from a configure until the session lets the camera go.
    private(set) var holdsCamera = true
    /// Session calls in order: "configure", "start", "release".
    private(set) var calls: [String] = []
    private(set) var recordingURLs: [URL] = []
    private(set) var stopRecordingCount = 0

    init(failingLensIDs: Set<String>, isClipInFlight: Bool = false,
         onStartRecording: @escaping @Sendable (URL, VideoOption) async -> Void = { _, _ in }) {
        self.failingLensIDs = failingLensIDs
        self.isClipInFlight = isClipInFlight
        self.onStartRecording = onStartRecording
    }

    /// From now on only these lenses fail to configure.
    func setFailingLensIDs(_ ids: Set<String>) {
        failingLensIDs = ids
    }

    func configure(_ configuration: SessionConfiguration) throws(CameraSessionError) {
        guard !failingLensIDs.contains(configuration.lens.id) else {
            throw .noMatchingFormat(option: "fake \(configuration.lens.id)")
        }
        applied.append(configuration)
        holdsCamera = true
        calls.append("configure")
    }

    func start() {
        isRunning = true
        calls.append("start")
    }

    func releaseCameras() {
        isRunning = false
        holdsCamera = false
        releaseCount += 1
        calls.append("release")
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
