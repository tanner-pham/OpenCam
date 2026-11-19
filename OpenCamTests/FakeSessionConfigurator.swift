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
    /// Session calls in order: "configure", "start", "release", "manual", "focus", "zoom".
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

    private var failsCombined = false

    /// From now on a configuration on the combined camera fails to configure; false stops that.
    func setFailsCombined(_ fails: Bool) {
        failsCombined = fails
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
        guard !(failsCombined && configuration.combined != nil) else {
            throw .noMatchingFormat(option: "fake combined")
        }
        guard !failingLensIDs.contains(configuration.lens.id) else {
            throw .noMatchingFormat(option: "fake \(configuration.lens.id)")
        }
        if !PinchZoom.keeps(from: applied.last, to: configuration) { storedPinch = 1 }
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
        // The phone refuses a custom exposure on the combined camera (measured 2026-11-16).
        if let last = applied.last, last.combined != nil, settings.exposure != .automatic {
            throw .notSupported(control: "exposure", lens: last.lens.id)
        }
        let plan = try ManualApplyPlan.make(settings, applied: reapplyingAll ? nil : appliedManual, limits: ranges, lens: "fake",
                                            isRAWClipRecording: false)
        appliedManual = plan.applied
        return plan.applied
    }

    // MARK: Focus

    /// Every request `applyFocus` received, in order.
    private(set) var focusRequests: [FocusRequest] = []
    private var focusOutcome = FocusOutcome.focusAndExposure
    private var isHoldingFocus = false
    private var heldFocus: [CheckedContinuation<Void, Never>] = []

    /// From now on `applyFocus` answers `outcome`.
    func setFocusOutcome(_ outcome: FocusOutcome) {
        focusOutcome = outcome
    }

    /// From now on a request is recorded ("focus"), then waits, until `resumeFocus`.
    func holdFocus() {
        isHoldingFocus = true
    }

    func resumeFocus() {
        isHoldingFocus = false
        for waiting in heldFocus { waiting.resume() }
        heldFocus = []
    }

    func applyFocus(_ request: FocusRequest) async -> FocusOutcome {
        focusRequests.append(request)
        calls.append("focus")
        if isHoldingFocus { await withCheckedContinuation { heldFocus.append($0) } }
        return focusOutcome
    }

    // MARK: Zoom

    /// Every pinch `applyZoom` received, in order.
    private(set) var zoomRequests: [Double] = []
    /// The most the fake camera's format holds; `applyZoom` answers no more than this.
    private(set) var zoomLimit = PinchZoom.cap
    /// What the camera holds now; a configure resets it by the same rule as the session's (`PinchZoom.keeps`).
    private var storedPinch = 1.0
    var pinch: Double { storedPinch }

    func setZoomLimit(_ limit: Double) {
        zoomLimit = limit
    }

    private var isHoldingZoom = false
    private var heldZoom: [CheckedContinuation<Void, Never>] = []

    /// From now on an apply is recorded ("zoom"), then waits, until `resumeZoom`.
    func holdZoom() {
        isHoldingZoom = true
    }

    func resumeZoom() {
        isHoldingZoom = false
        for waiting in heldZoom { waiting.resume() }
        heldZoom = []
    }

    func applyZoom(pinch: Double) async -> Double {
        zoomRequests.append(pinch)
        calls.append("zoom")
        if isHoldingZoom { await withCheckedContinuation { heldZoom.append($0) } }
        storedPinch = min(pinch, zoomLimit)
        return storedPinch
    }
}
