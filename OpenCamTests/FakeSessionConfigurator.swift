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
        // A configure returns the camera to automatic, as the session does.
        appliedManual = nil
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
        appliedManual = nil
        isRunning = false
        holdsCamera = false
        releaseCount += 1
        calls.append("release")
    }

    /// Records "release" exactly as `releaseCameras()` does; a test feeds `.savedStartReleased` to the model itself.
    func releaseSavedStart() {
        releaseCameras()
    }

    // MARK: Recorder path (the protocol's startRecording, with the writer's drop policy). Kept in one block so other
    // protocol additions merge beside it, not through it.

    /// Every start, with the drop policy it carried; `recordingURLs` keeps just the URLs.
    private(set) var recordings: [(url: URL, option: VideoOption, dropPolicy: DropPolicy)] = []

    func startRecording(option: VideoOption, url: URL, minFreeBytes: Int64, dropPolicy: DropPolicy) async throws(RecordingError) {
        recordingURLs.append(url)
        recordings.append((url, option, dropPolicy))
        await onStartRecording(url, option)
    }

    // MARK: End of the recorder path block

    func stopRecording() -> Bool {
        stopRecordingCount += 1
        return isClipInFlight
    }

    // MARK: Manual controls

    /// A full, plausible set, so a test that never calls `setRanges` still goes through the session's clamping.
    static let defaultRanges = ManualRanges(shutterSeconds: (1.0 / 8000)...(1.0 / 3), iso: 34...6400, bias: -2...2,
                                            hasWhiteBalance: true, hasFocus: true)

    /// What `manualRanges()` answers and `applyManual` plans against; nil means no camera to adjust.
    private var ranges: ManualRanges? = FakeSessionConfigurator.defaultRanges
    private var readouts = LiveReadouts()
    private var manualError: ManualControlError?
    private(set) var manualApplies: [(settings: ManualSettings, reapplyingAll: Bool)] = []
    /// What the last apply left on the camera, as the session keeps it; nil after a configure or a release.
    private(set) var appliedManual: ManualSettings?
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

    /// From now on an apply is recorded ("manual"), then waits, until `resumeManual`; "manual done" follows when it ends.
    func holdManual() {
        isHoldingManual = true
    }

    func resumeManual() {
        isHoldingManual = false
        for waiting in heldManual { waiting.resume() }
        heldManual = []
    }

    /// Empty while the fake is not running or holds no camera, as the session's is.
    func currentReadouts() -> LiveReadouts {
        guard isRunning, holdsCamera else { return LiveReadouts() }
        return readouts
    }

    func manualRanges() -> ManualRanges? {
        guard isRunning, holdsCamera else { return nil }
        return ranges
    }

    /// Plans with `ManualApplyPlan.make` against its ranges and its last applied settings, as the session does, and returns what
    /// the plan says the camera has. Refuses with `.noCamera` when not running, holding no camera or without ranges.
    func applyManual(_ settings: ManualSettings, reapplyingAll: Bool) async throws(ManualControlError) -> ManualSettings {
        manualApplies.append((settings, reapplyingAll))
        calls.append("manual")
        defer { calls.append("manual done") }
        guard isRunning, holdsCamera, let ranges else { throw .noCamera }
        if isHoldingManual { await withCheckedContinuation { heldManual.append($0) } }
        if let manualError { throw manualError }
        let plan = try ManualApplyPlan.make(settings, applied: reapplyingAll ? nil : appliedManual, limits: ranges, lens: "fake",
                                            isRAWClipRecording: false)
        appliedManual = plan.applied
        return plan.applied
    }
}
