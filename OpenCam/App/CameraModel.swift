import AVKit
import Foundation
import Observation
import OSLog

@Observable
final class CameraModel {
    private static let logger = Logger(subsystem: "local.opencam.app", category: "CameraModel")
    private static let simulatorFreeBytes: Int64 = 141_000_000_000
    private static let placeholderRecord = RecordSelection(family: .hevc, quality: "High", resolution: .named(width: 3840, height: 2160), frameRate: 30, colour: .rec709)
    private static let placeholderPhoto = PhotoSelection(format: .heif, megapixels: 12)

    var mode: CaptureMode { didSet { selectionChanged() } }
    var record: RecordSelection { didSet { selectionChanged() } }
    var photo: PhotoSelection { didSet { selectionChanged() } }
    var sheet: CameraSheet?
    var phase: CameraPhase
    var freeBytes: Int64
    /// Set only through `show(_:from:)` and cleared only through `clearNotice(from:)`, so each event clears only its own.
    private(set) var notice: String?
    private(set) var meterLevels: [Double] = []
    var lastCapture: URL?
    private(set) var capabilities: CaptureCapabilities
    private(set) var lensID: String { didSet { selectionChanged() } }
    private(set) var isRecording: Bool
    private(set) var recordingStart: Date?
    private(set) var access: CaptureAccess
    private(set) var pressureLevel: PressureLevel = .nominal
    private(set) var isThermalPressure = false
    /// True while the scanner sets formats on the cameras (first scan or rescan). Lens and mode cannot change then,
    /// and no configure is queued; the selection in force when the scan ends is configured afterwards.
    private(set) var isScanningFormats = false
    /// The camera's live values, polled while the session runs; shown only through `shownReadouts`.
    private(set) var readouts = LiveReadouts()

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let isScripted: Bool
    /// The Simulator keeps the stand-in free space; the device reads it.
    @ObservationIgnored private let isSimulator: Bool
    /// `-freeSpaceMarginMB N`: recording stops N MB before the volume is full, in place of the 2 GB reserve, to test that path.
    @ObservationIgnored private let freeSpaceMarginMB: Int?
    @ObservationIgnored private let capabilitySource: CapabilitySource
    /// Set by `attachSession` once the session has a working configuration; from then on selection changes reconfigure it.
    @ObservationIgnored private var configurator: (any SessionConfigurator)?
    /// The tail of the serial configure chain; each task returns its configure error, or nil.
    @ObservationIgnored private var configureTask: Task<CameraSessionError?, Never>?
    /// Bumped per requested configuration; a queued configure that is no longer the latest is skipped.
    @ObservationIgnored private var configureGeneration = 0
    /// The configuration last sent to the chain, so an unchanged selection does not reconfigure.
    @ObservationIgnored private var requestedConfiguration: SessionConfiguration?
    /// What the session last applied, and the selection that produced it; a failed configure returns to them.
    @ObservationIgnored private var lastWorking: (configuration: SessionConfiguration, selection: SavedSelections)?
    /// True while several selection properties are set as one change (a restore or a capabilities load);
    /// the caller persists and reconfigures once at the end.
    @ObservationIgnored private var isApplyingSelection = false
    /// True from a launch without capabilities until real ones arrive; nothing is saved meanwhile.
    @ObservationIgnored private var isAwaitingRestore: Bool
    /// The running session, for capture; set by `start(session:)`.
    @ObservationIgnored private var cameraSession: CameraSession?
    /// Created on the first capture.
    @ObservationIgnored private var captureStore: CaptureStore?
    /// Photo captures still running, by file number. A configure queued after a press waits for them,
    /// because Bayer RAW needs the zoom unchanged until the capture ends (AVCapturePhotoOutput.h).
    @ObservationIgnored private var photoCaptures: [Int: Task<Void, Never>] = [:]
    /// The start of the recording in flight, so a stop pressed while it is still starting waits for it.
    @ObservationIgnored private var recordingStartTask: Task<Void, Never>?
    /// What put `notice` there; nil when no notice is shown.
    @ObservationIgnored private var noticeSource: NoticeSource?

    static let formatFailedNotice = "That format could not be used."
    static let formatSetupFailed = "This format could not be set up."
    init(config: LaunchConfig, capabilities: CaptureCapabilities, isSimulator: Bool, defaults: UserDefaults = .standard,
         capabilitySource: CapabilitySource = .device) {
        self.capabilities = capabilities
        self.defaults = defaults
        self.capabilitySource = capabilitySource
        self.isScripted = config.isScripted
        self.isSimulator = isSimulator
        self.freeSpaceMarginMB = config.freeSpaceMarginMB
        if isSimulator {
            self.phase = config.simulatedState == .scanning ? .scanning : .simulator
        } else {
            self.phase = .scanning
        }
        let accessState: AccessState = isSimulator ? .authorized : .notDetermined
        self.access = CaptureAccess(camera: accessState, microphone: accessState)
        self.freeBytes = Self.simulatorFreeBytes
        self.isRecording = config.isRecording
        self.recordingStart = config.isRecording ? Date().addingTimeInterval(-42) : nil
        switch config.screen {
        case .main: self.sheet = nil
        case .record: self.sheet = .record
        case .sweep: self.sheet = .sweep
        }

        let saved = config.isScripted ? nil : SavedSelections.load(from: defaults)
        let resolved = Self.resolve(lensID: saved?.lensID, record: saved?.record, photo: saved?.photo, in: capabilities)
        self.lensID = resolved.lensID
        self.mode = saved?.mode ?? config.mode
        self.record = resolved.record ?? Self.placeholderRecord
        self.photo = resolved.photo ?? Self.placeholderPhoto
        // A device launch starts with no capabilities, so the saved choices wait for real ones and must not be overwritten meanwhile.
        self.isAwaitingRestore = !config.isScripted && capabilities.lenses.isEmpty
        if isSimulator { simulate(config.simulatedState) }
    }

    /// Puts the Simulator in a state the device would reach, for screenshots; `scanning` is set with the phase.
    private func simulate(_ state: SimulatedState?) {
        switch state {
        case .cameraDenied:
            phase = .cameraDenied
            access.camera = .denied
        case .micDenied:
            access.microphone = .denied
        case .lowStorage:
            if let option = currentVideoOption {
                let bytesPerMinute = DataRateEstimator.gigabytesPerMinute(for: option) * 1_000_000_000
                freeBytes = DataRateEstimator.reserveBytes + Int64(4.5 * bytesPerMinute)
            }
        case .storageFull:
            freeBytes = 1_500_000_000
        case .pressure:
            pressureLevel = .serious
            isThermalPressure = true
        case .scanning, nil:
            break
        }
    }

    var lenses: [Lens] { capabilities.lenses }
    var currentLens: Lens? { capabilities.lenses.first { $0.id == lensID } }

    var recordResolver: RecordSelectionResolver {
        RecordSelectionResolver(options: capabilities.videoOptions, lens: currentLens)
    }

    var photoResolver: PhotoSelectionResolver {
        PhotoSelectionResolver(options: capabilities.photoOptions, lenses: capabilities.lenses, lensID: lensID)
    }

    var currentVideoOption: VideoOption? { recordResolver.option(for: record) }
    var currentPhotoOption: PhotoOption? { photoResolver.option(for: photo) }

    /// What the session should capture for the current selection; nil without a lens.
    var sessionConfiguration: SessionConfiguration? {
        guard let currentLens else { return nil }
        return SessionConfiguration.make(lens: currentLens, mode: mode, video: currentVideoOption, photo: currentPhotoOption, access: access)
    }

    /// The current options as the screen may name them: none while formats are being read, and none the device has not reported.
    /// Only a working camera, or the Simulator's labelled stand-in, names a format or a measurement.
    private var hasCamera: Bool { phase == .ready || phase == .simulator }
    private var shownVideoOption: VideoOption? { hasCamera ? currentVideoOption : nil }
    private var shownPhotoOption: PhotoOption? { hasCamera ? currentPhotoOption : nil }

    /// Levels only from a running session with a microphone; otherwise both bars read empty.
    var shownMeterLevels: [Double] {
        phase == .ready && access.recordsSound && meterLevels.count == 2 ? meterLevels : [0, 0]
    }

    var summaryParts: [String] {
        switch mode {
        case .video:
            guard let option = shownVideoOption else { return ["--"] }
            return [option.codec.family.title, option.resolution.label, option.colour.shortName]
        case .photo:
            guard let option = shownPhotoOption else { return ["--"] }
            return [option.format.rawValue, option.label]
        }
    }

    var frameRateText: String {
        shownVideoOption.map { String($0.frameRate) } ?? "--"
    }

    /// The timecode counts frames at the rate the FPS readout shows, 30 when none is shown.
    var timecodeFrameRate: Int { shownVideoOption?.frameRate ?? 30 }

    /// Live values only while the camera is ready; otherwise (Simulator, scanning, no camera) every readout reads `--`.
    var shownReadouts: LiveReadouts { phase == .ready ? readouts : LiveReadouts() }
    var shutterText: String { ReadoutFormatter.shutter(shownReadouts.shutterSeconds) }
    var isoText: String { ReadoutFormatter.iso(shownReadouts.iso) }
    var whiteBalanceText: String { ReadoutFormatter.kelvin(shownReadouts.kelvin) }
    var tintText: String { ReadoutFormatter.tint(shownReadouts.tint) }
    var exposureBiasText: String { ReadoutFormatter.bias(shownReadouts.exposureBias) }
    var focusText: String { ReadoutFormatter.focus(shownReadouts.lensPosition) }

    private var minutesRemaining: Int {
        currentVideoOption.map { DataRateEstimator.minutesRemaining(freeBytes: freeBytes, option: $0) } ?? 0
    }

    /// "-- min" until a video format is known, then the minutes left, or "Storage full" at 0.
    var remaining: RemainingTime {
        guard shownVideoOption != nil else { return RemainingTime(text: "-- min", isWarning: false) }
        return StatusText.remaining(minutes: minutesRemaining)
    }
    var remainingText: String { remaining.text }
    var isStorageFull: Bool { remaining.text == StatusText.storageFull }

    var pressureText: String? { StatusText.pressure(pressureLevel, isThermal: isThermalPressure) }

    /// The one line under the controls; photo mode never mentions the microphone, which photos do not use.
    var bottomNotice: String? {
        let usedAccess = mode == .video ? access : CaptureAccess(camera: access.camera, microphone: .authorized)
        return StatusText.bottomNotice(access: usedAccess, pressure: pressureText, notice: notice)
    }

    /// True when `bottomNotice` is the microphone line, which Settings can fix.
    var bottomNoticeOpensSettings: Bool {
        bottomNotice == StatusText.microphoneOff
    }

    /// Record settings opens only once the device's formats are known.
    var canOpenRecordSettings: Bool {
        hasCamera && !(capabilities.videoOptions.isEmpty && capabilities.photoOptions.isEmpty)
    }

    func openRecordSettings() {
        guard canOpenRecordSettings else { return }
        sheet = .record
    }

    /// Audio meters and the remaining-time estimate describe video recording, so photo mode hides them.
    var showsVideoReadouts: Bool { mode == .video }

    var canCapture: Bool {
        guard StatusText.canRecord(phase: phase, mode: mode, minutesRemaining: minutesRemaining) else { return false }
        switch mode {
        case .video: return currentVideoOption != nil
        case .photo: return currentPhotoOption != nil
        }
    }

    /// The strip's Lens and Mode items follow this; `isScanningFormats` also keeps configures from queuing.
    var canChangeLensOrMode: Bool { !isRecording && !isScanningFormats }

    func selectLens(_ id: String) {
        guard id != lensID, capabilities.lenses.contains(where: { $0.id == id }) else { return }
        lensID = id
        settleSelections()
    }

    /// On a launch that is not scripted, the saved mode, lens and selections are applied again and settled against
    /// the new capabilities: a missing lens becomes the default lens, and selections move to the nearest valid one.
    func replaceCapabilities(_ capabilities: CaptureCapabilities) {
        let saved = isScripted ? nil : SavedSelections.load(from: defaults)
        let candidate = saved ?? currentSelection
        let resolved = Self.resolve(lensID: candidate.lensID, record: candidate.record, photo: candidate.photo, in: capabilities)
        self.capabilities = capabilities
        isApplyingSelection = true
        lensID = resolved.lensID
        if let saved { mode = saved.mode }
        record = resolved.record ?? record
        photo = resolved.photo ?? photo
        isApplyingSelection = false
        isAwaitingRestore = false
        selectionChanged()
    }

    /// In video mode a press starts recording, or stops it.
    func capturePressed() {
        perform(.forPress(mode: mode, isRecording: isRecording))
    }

    /// The one path for the on-screen button and the Camera Control: stopping is always allowed,
    /// a photo or a new recording only when `canCapture`.
    private func perform(_ action: CaptureAction) {
        switch action {
        case .stopRecording:
            stopRecording()
        case .takePhoto:
            guard canCapture else { return }
            capturePhoto()
        case .startRecording:
            guard canCapture else { return }
            startRecording()
        }
    }

    /// Offers the newest photo or clip already in the captures folder; a capture made since then stays.
    func loadLastCapture() {
        guard lastCapture == nil else { return }
        if captureStore == nil {
            do throws(CaptureStoreError) {
                captureStore = try CaptureStore.appDefault()
            } catch {
                Self.logger.error("\(error.description, privacy: .public)")
                return
            }
        }
        lastCapture = captureStore?.latestCapture()
    }

    /// The captures folder, created on first use; nil, with `failureNotice` shown, when it cannot be.
    private func store(failureNotice: String) -> CaptureStore? {
        if let captureStore { return captureStore }
        do throws(CaptureStoreError) {
            let store = try CaptureStore.appDefault()
            captureStore = store
            return store
        } catch {
            Self.logger.error("\(error.description, privacy: .public)")
            show(failureNotice, from: .capture)
            return nil
        }
    }

    /// Reserves a file number now, so quick presses never share one, then captures behind any queued configure.
    /// RAW and HEIF of one press share the number. The notice and `lastCapture` follow `PhotoSaveReport`.
    private func capturePhoto() {
        guard let cameraSession, let option = currentPhotoOption,
              let store = store(failureNotice: PhotoSaveReport.photoNotSaved) else { return }
        let sequence = store.reserveSequence()
        let dngURL = store.url(sequence: sequence, kind: .dng)
        let heicURL = store.url(sequence: sequence, kind: .heic)
        var requested: [URL] = []
        if option.format.includesRAW { requested.append(dngURL) }
        if option.format != .raw { requested.append(heicURL) }
        let pendingConfigure = configureTask
        photoCaptures[sequence] = Task {
            defer { photoCaptures[sequence] = nil }
            _ = await pendingConfigure?.value
            let result: PhotoCaptureResult
            do throws(PhotoCaptureError) {
                result = try await cameraSession.capturePhoto(format: option.format, dngURL: dngURL, heicURL: heicURL)
            } catch {
                result = PhotoCaptureResult(saved: [], error: error)
            }
            photoFinished(requested: requested, result: result)
        }
    }

    /// The notice always describes the latest capture: a full save clears an earlier photo notice.
    private func photoFinished(requested: [URL], result: PhotoCaptureResult) {
        if let error = result.error {
            Self.logger.error("\(error.description, privacy: .public)")
        }
        let report = PhotoSaveReport.make(requested: requested, saved: result.saved, error: result.error)
        if let saved = report.lastCapture { lastCapture = saved }
        // A full save replaces an earlier capture notice with none.
        if let reportNotice = report.notice {
            show(reportNotice, from: .capture)
        } else {
            clearNotice(from: .capture)
        }
        refreshFreeBytes()
    }

    /// Reserves a file number and starts recording behind any queued configure. `isRecording` holds from the press,
    /// so lens, mode and format stay as they are until `recordingDidFinish`.
    private func startRecording() {
        guard let cameraSession, let option = currentVideoOption,
              let store = store(failureNotice: RecordingOutcome.failedNotice) else { return }
        let url = store.url(sequence: store.reserveSequence(), kind: .mov)
        let minFreeBytes = recordingReserveBytes()
        let pendingConfigure = configureTask
        isRecording = true
        recordingStartTask = Task {
            if let configureError = await pendingConfigure?.value {
                // The session went back to its last working format, which is not the one the press was for.
                recordingDidFinish(RecordingResult(url: url, option: option, outcome: .failed(configureError.description), sidecar: nil))
                return
            }
            do throws(RecordingError) {
                try await cameraSession.startRecording(option: option, url: url, minFreeBytes: minFreeBytes)
                recordingStart = Date()
            } catch {
                recordingDidFinish(RecordingResult(url: url, option: option, outcome: .failed(error.description), sidecar: nil))
            }
        }
    }

    /// Waits for a recording that is still starting, then stops it; the UI resets in `recordingDidFinish`.
    private func stopRecording() {
        guard let cameraSession else { return }
        let start = recordingStartTask
        Task {
            await start?.value
            await cameraSession.stopRecording()
        }
    }

    /// The free space at which recording stops: the 2 GB reserve, or free space minus the `-freeSpaceMarginMB` margin.
    private func recordingReserveBytes() -> Int64 {
        guard let freeSpaceMarginMB else { return DataRateEstimator.reserveBytes }
        return max(0, FreeSpace.availableBytes() - Int64(freeSpaceMarginMB) * 1_000_000)
    }

    /// The Simulator keeps its stand-in figure.
    private func refreshFreeBytes() {
        guard !isSimulator else { return }
        freeBytes = FreeSpace.availableBytes()
    }

    /// Waits for every photo capture already running.
    private func waitForPhotoCaptures() async {
        for capture in Array(photoCaptures.values) {
            await capture.value
        }
    }

    private func settleSelections() {
        record = Self.settle(record, with: recordResolver) ?? record
        photo = Self.settle(photo, with: photoResolver) ?? photo
    }

    var currentSelection: SavedSelections {
        SavedSelections(mode: mode, lensID: lensID, record: record, photo: photo)
    }

    private func selectionChanged() {
        guard !isApplyingSelection else { return }
        persist()
        enqueueConfigure()
    }

    private func persist() {
        guard !isScripted, !isAwaitingRestore else { return }
        currentSelection.save(to: defaults)
    }

    /// Hands the model a session already running `configuration`, which was built from `selection`;
    /// later selection changes reconfigure it.
    func attachSession(_ configurator: any SessionConfigurator, configuredWith configuration: SessionConfiguration, selection: SavedSelections) {
        self.configurator = configurator
        requestedConfiguration = configuration
        lastWorking = (configuration, selection)
        // A change made while the first configure was awaited could not queue yet; apply it now.
        enqueueConfigure()
    }

    /// Applies the current selection behind any configure already queued, and throws if it could not be used.
    /// After a failure the session, the selection and `phase` stay as they were before, and `notice` says so.
    func applySelection() async throws(CameraSessionError) {
        guard let task = enqueueConfigure() ?? configureTask else { return }
        if let error = await task.value { throw error }
    }

    /// Waits for every configure already queued, without queuing one.
    func waitForQueuedConfigures() async {
        _ = await configureTask?.value
    }

    /// Queues a configure behind any running one. A lens switch changes lens, record and photo in one turn;
    /// only the last of those runs, because the earlier ones are superseded before the chain reaches them.
    @discardableResult
    private func enqueueConfigure() -> Task<CameraSessionError?, Never>? {
        guard !isScanningFormats, !isRecording, let configurator, let configuration = sessionConfiguration, configuration != requestedConfiguration else { return nil }
        requestedConfiguration = configuration
        configureGeneration += 1
        let generation = configureGeneration
        let selection = currentSelection
        let previous = configureTask
        let captures = Array(photoCaptures.values)
        let task = Task { () -> CameraSessionError? in
            _ = await previous?.value
            for capture in captures {
                await capture.value
            }
            guard generation == configureGeneration else { return nil }
            do throws(CameraSessionError) {
                try await configurator.configure(configuration)
            } catch {
                configureFailed(error, generation: generation)
                return error
            }
            lastWorking = (configuration, selection)
            clearNotice(from: .configuration)
            return nil
        }
        configureTask = task
        return task
    }

    /// The session has already restored its last working configuration; the selection follows it,
    /// unless a newer selection is queued, which then stands.
    private func configureFailed(_ error: CameraSessionError, generation: Int) {
        Self.logger.error("\(error.description, privacy: .public)")
        guard let lastWorking else {
            phase = .failed(Self.formatSetupFailed)
            return
        }
        show(Self.formatFailedNotice, from: .configuration)
        guard generation == configureGeneration else { return }
        isApplyingSelection = true
        lensID = lastWorking.selection.lensID
        mode = lastWorking.selection.mode
        record = lastWorking.selection.record
        photo = lastWorking.selection.photo
        isApplyingSelection = false
        requestedConfiguration = lastWorking.configuration
        configureTask = nil
        persist()
    }

    private static func defaultLens(in capabilities: CaptureCapabilities) -> Lens? {
        capabilities.lenses.first { $0.kind == .wide && $0.zoomFactor == 1 } ?? capabilities.lenses.first
    }

    /// The lens if it exists, else the default lens; each selection settled to the nearest valid one, else that lens's default.
    /// A nil selection means none exists for the lens.
    private static func resolve(lensID: String?, record: RecordSelection?, photo: PhotoSelection?, in capabilities: CaptureCapabilities)
        -> (lensID: String, record: RecordSelection?, photo: PhotoSelection?) {
        let lensID = lensID.flatMap { id in capabilities.lenses.contains { $0.id == id } ? id : nil } ?? defaultLens(in: capabilities)?.id ?? ""
        let lens = capabilities.lenses.first { $0.id == lensID }
        let recordResolver = RecordSelectionResolver(options: capabilities.videoOptions, lens: lens)
        let photoResolver = PhotoSelectionResolver(options: capabilities.photoOptions, lenses: capabilities.lenses, lensID: lensID)
        return (lensID, settle(record, with: recordResolver), settle(photo, with: photoResolver))
    }

    private static func settle(_ selection: RecordSelection?, with resolver: RecordSelectionResolver) -> RecordSelection? {
        selection.flatMap(resolver.settled) ?? resolver.defaultSelection()
    }

    private static func settle(_ selection: PhotoSelection?, with resolver: PhotoSelectionResolver) -> PhotoSelection? {
        selection.flatMap(resolver.settled) ?? resolver.defaultSelection()
    }
}

extension CameraModel {
    /// Asks for access, loads the device's capabilities in place of the fixture, configures and starts the session,
    /// then follows its events for as long as the calling task runs.
    func start(session: CameraSession) async {
        refreshFreeBytes()
        access = await CameraSession.requestAccess()
        guard access.canUseCamera else {
            phase = access.camera == .restricted ? .cameraRestricted : .cameraDenied
            return
        }
        let lenses = capabilitySource.discoverLenses()
        guard !lenses.isEmpty else {
            Self.logger.error("[CameraModel:start] No camera found — {lenses: 0}")
            phase = .failed("The camera could not start.")
            return
        }
        await loadCapabilities(lenses: lenses)
        if case .failed = phase { return }
        guard let configuration = sessionConfiguration else {
            Self.logger.error("[CameraModel:start] No lens selected — {lenses: \(lenses.count)}")
            phase = .failed("The camera could not start.")
            return
        }
        let selection = currentSelection
        do {
            try await session.configure(configuration)
        } catch {
            Self.logger.error("\(error.description, privacy: .public)")
            phase = .failed(Self.formatSetupFailed)
            return
        }
        attachSession(session, configuredWith: configuration, selection: selection)
        cameraSession = session
        await session.start()
        phase = .ready
        await withDiscardingTaskGroup { group in
            group.addTask { await self.followRecordings(of: session) }
            group.addTask { await self.pollMeters(of: session) }
            group.addTask { await self.pollReadouts(of: session) }
            for await event in session.events {
                apply(event)
            }
            group.cancelAll()
        }
    }

    private func followRecordings(of session: CameraSession) async {
        for await result in session.recordings {
            recordingDidFinish(result)
        }
    }

    /// Ten times a second; the levels stay empty without a microphone.
    private func pollMeters(of session: CameraSession) async {
        while !Task.isCancelled {
            let levels = await session.audioLevels()
            if levels != meterLevels { meterLevels = levels }
            do {
                try await Task.sleep(for: .milliseconds(100))
            } catch {
                return
            }
        }
    }

    /// Four times a second while ready; the session reads whichever camera is current, so a lens switch needs nothing here,
    /// and reports nothing while stopped.
    private func pollReadouts(of session: CameraSession) async {
        while !Task.isCancelled {
            let latest = phase == .ready ? await session.currentReadouts() : LiveReadouts()
            if latest != readouts { readouts = latest }
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
        }
    }

    /// Resets the record button and timecode, keeps a playable clip as the last capture, and says what happened:
    /// the outcome's notice, else dropped frames, else nothing (clearing an earlier recording notice).
    /// A selection change held back while recording is applied now.
    func recordingDidFinish(_ result: RecordingResult) {
        isRecording = false
        recordingStart = nil
        recordingStartTask = nil
        if case .failed(let message) = result.outcome {
            Self.logger.error("\(message, privacy: .public)")
        }
        if result.outcome.isPlayable { lastCapture = result.url }
        let clipName = result.url.deletingPathExtension().lastPathComponent
        // An unknown dropped-frame count gives no notice.
        let recordingNotice = result.outcome.notice ?? result.sidecar?.actual?.droppedFrames.flatMap {
            RecordingOutcome.droppedFramesNotice(clipName: clipName, droppedFrames: $0)
        }
        if let recordingNotice {
            show(recordingNotice, from: .capture)
        } else {
            clearNotice(from: .capture)
        }
        refreshFreeBytes()
        enqueueConfigure()
    }

    /// Uses the cached capabilities when they were written on this OS build and model and all their lenses are present
    /// (lenses a scan skipped stay out until `rescanCapabilities`); otherwise scans.
    func loadCapabilities(lenses: [Lens]) async {
        let cache = CapabilityCache(directory: capabilitySource.cacheDirectory)
        if let cached = cache.load(osBuild: DeviceIdentity.osBuild(), modelIdentifier: DeviceIdentity.modelIdentifier()),
           let adopted = cached.adopting(discovered: lenses) {
            replaceCapabilities(adopted)
            return
        }
        phase = .scanning
        guard let capabilities = await scanCapabilities(lenses: lenses) else {
            phase = .failed("The camera could not start.")
            return
        }
        adoptScan(capabilities, lenses: lenses)
    }

    /// Off while recording or while formats are being read.
    var canRescanCapabilities: Bool { !isRecording && phase != .scanning && phase != .simulator }

    /// Clears the cache and reads every camera again, for a camera that could not be read before. The session is stopped
    /// meanwhile, because the scan sets each camera's format directly; the saved selections are restored afterwards.
    func rescanCapabilities() async {
        guard canRescanCapabilities else { return }
        do {
            try CapabilityCache(directory: capabilitySource.cacheDirectory).clear()
        } catch {
            Self.logger.error("\(error.description, privacy: .public)")
        }
        let previousPhase = phase
        phase = .scanning
        // No configure may queue from here, and none already queued may still be running when the scanner touches the cameras.
        isScanningFormats = true
        await waitForQueuedConfigures()
        await waitForPhotoCaptures()
        await configurator?.stop()
        let lenses = capabilitySource.discoverLenses()
        let capabilities = await scanCapabilities(lenses: lenses)
        phase = previousPhase
        // The scan moved the cameras' formats, so the session is configured again even when the selection is unchanged.
        requestedConfiguration = nil
        if let capabilities {
            adoptScan(capabilities, lenses: lenses)
        } else {
            show(Self.rescanFailedNotice, from: .scan)
        }
        try? await applySelection()
        await configurator?.start()
    }

    static let rescanFailedNotice = "Camera formats could not be read."

    static func skippedCamerasNotice(count: Int) -> String? {
        switch count {
        case 0: nil
        case 1: "1 camera could not be read."
        default: "\(count) cameras could not be read."
        }
    }

    /// Nil when the scan failed or no camera reported a usable format; the reason is logged.
    private func scanCapabilities(lenses: [Lens]) async -> CaptureCapabilities? {
        isScanningFormats = true
        defer { isScanningFormats = false }
        let formats: [FormatDescriptor]
        do {
            formats = try await capabilitySource.scan(lenses)
        } catch {
            Self.logger.error("\(error.description, privacy: .public)")
            return nil
        }
        let capabilities = CapabilityMapper.capabilities(lenses: lenses, formats: formats,
                                                         osBuild: DeviceIdentity.osBuild(), modelIdentifier: DeviceIdentity.modelIdentifier())
        guard !capabilities.lenses.isEmpty else {
            Self.logger.error("[CameraModel:scanCapabilities] No camera reported a usable format — {lenses: \(lenses.count), formats: \(formats.count)}")
            return nil
        }
        return capabilities
    }

    /// Applies a finished scan, says how many cameras were skipped, saves it to the cache and leaves a copy
    /// in Documents for comparison with the probe report.
    private func adoptScan(_ capabilities: CaptureCapabilities, lenses: [Lens]) {
        replaceCapabilities(capabilities)
        // This scan worked, so an earlier scan's notice is stale.
        clearNotice(from: .scan)
        // Notices count cameras, and a skipped camera can carry two lenses (1x and 2x).
        let skipped = Set(lenses.filter { capabilities.skippedLensIDs.contains($0.id) }.map(\.deviceUniqueID))
        if let skippedNotice = Self.skippedCamerasNotice(count: skipped.count) {
            show(skippedNotice, from: .scan)
        }
        for directory in [capabilitySource.cacheDirectory, capabilitySource.documentsDirectory].compactMap({ $0 }) {
            do {
                try CapabilityCache(directory: directory).save(capabilities)
            } catch {
                Self.logger.error("\(error.description, privacy: .public)")
            }
        }
    }

    private func show(_ text: String, from source: NoticeSource) {
        notice = text
        noticeSource = source
    }

    /// Clears the notice only when `source` put it there.
    private func clearNotice(from source: NoticeSource) {
        guard noticeSource == source else { return }
        notice = nil
        noticeSource = nil
    }

    func apply(_ event: SessionEvent) {
        switch event {
        case .interrupted(let reason):
            // An interruption without a notice (backgrounding) changes nothing; one with a notice never covers a capture notice.
            if let interruptionNotice = reason.notice, noticeSource != .capture {
                show(interruptionNotice, from: .interruption)
            }
        case .interruptionEnded:
            clearNotice(from: .interruption)
        case .runtimeError(let message):
            // Sets no notice; the phase says the camera stopped.
            Self.logger.error("\(message, privacy: .public)")
            phase = .failed("The camera stopped.")
        case .restarted:
            // The session runs again, so a pause notice is stale; any other notice stays.
            phase = .ready
            clearNotice(from: .interruption)
        case .microphoneUnavailable(let message):
            // Reads the same as microphone denied: video still records, without sound.
            Self.logger.error("\(message, privacy: .public)")
            access.microphone = .denied
        case .pressure(let level, let isThermal):
            pressureLevel = level
            isThermalPressure = isThermal
        }
    }
}

extension CameraModel {
    /// A Camera Control press: the same action and the same rules as the on-screen button.
    func handleCaptureEvent(phase: AVCaptureEventPhase) {
        guard let action = CaptureAction.forEvent(phase: phase, mode: mode, isRecording: isRecording) else { return }
        perform(action)
    }
}
