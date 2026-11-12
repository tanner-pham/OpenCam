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
    /// Session calls in order: "configure", "start", "release", "manual".
    private(set) var calls: [String] = []
    private(set) var recordingURLs: [URL] = []
    private(set) var stopRecordingCount = 0
    /// Runs once, inside the next `start()`, before it returns.
    private var onNextStart: (@Sendable () async -> Void)?

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

    private var isHolding = false
    private var held: [CheckedContinuation<Void, Never>] = []

    /// From now on a configure waits, before it does anything, until `resumeConfigures`.
    func holdConfigures() {
        isHolding = true
    }

    func resumeConfigures() {
        isHolding = false
        for waiting in held { waiting.resume() }
        held = []
    }

    func configure(_ configuration: SessionConfiguration) async throws(CameraSessionError) {
        if isHolding { await withCheckedContinuation { held.append($0) } }
        guard !failingLensIDs.contains(configuration.lens.id) else {
            throw .noMatchingFormat(option: "fake \(configuration.lens.id)")
        }
        applied.append(configuration)
        holdsCamera = true
        calls.append("configure")
    }

    func start() async {
        isRunning = true
        calls.append("start")
        let hook = onNextStart
        onNextStart = nil
        await hook?()
    }

    func setOnNextStart(_ hook: @escaping @Sendable () async -> Void) {
        onNextStart = hook
    }

    func releaseCameras() {
        isRunning = false
        holdsCamera = false
        releaseCount += 1
        calls.append("release")
    }

    /// Records "release" exactly as `releaseCameras()` does; a test feeds `.savedStartReleased` to the model itself.
    func releaseSavedStart() {
        releaseCameras()
    }

    func startRecording(option: VideoOption, url: URL, minFreeBytes: Int64) async throws(RecordingError) {
        recordingURLs.append(url)
        await onStartRecording(url, option)
    }

    func stopRecording() -> Bool {
        stopRecordingCount += 1
        return isClipInFlight
    }

    // MARK: Manual controls

    /// What `manualRanges()` answers and `applyManual` clamps to; nil reads as no camera, and an apply then returns its settings as they are.
    private var ranges: ManualRanges?
    private var readouts = LiveReadouts()
    private var manualError: ManualControlError?
    private(set) var manualApplies: [(settings: ManualSettings, reapplyingAll: Bool)] = []
    private var isHoldingManual = false
    private var heldManual: [CheckedContinuation<Void, Never>] = []

    func setReadouts(_ readouts: LiveReadouts) {
        self.readouts = readouts
    }

    func setRanges(_ ranges: ManualRanges?) {
        self.ranges = ranges
    }

    /// From now on `applyManual` throws `error`; nil stops that.
    func setManualError(_ error: ManualControlError?) {
        manualError = error
    }

    /// From now on an apply is recorded, then waits, before it returns, until `resumeManual`.
    func holdManual() {
        isHoldingManual = true
    }

    func resumeManual() {
        isHoldingManual = false
        for waiting in heldManual { waiting.resume() }
        heldManual = []
    }

    func currentReadouts() -> LiveReadouts {
        readouts
    }

    func manualRanges() -> ManualRanges? {
        ranges
    }

    func applyManual(_ settings: ManualSettings, reapplyingAll: Bool) async throws(ManualControlError) -> ManualSettings {
        manualApplies.append((settings, reapplyingAll))
        calls.append("manual")
        if isHoldingManual { await withCheckedContinuation { heldManual.append($0) } }
        if let manualError { throw manualError }
        return ranges?.clamped(settings) ?? settings
    }
}
