import AVKit
import Foundation
import Observation
import OSLog

@Observable
final class CameraModel {
    static let logger = Logger(subsystem: "local.opencam.app", category: "CameraModel")
    private static let simulatorFreeBytes: Int64 = 141_000_000_000
    private static let placeholderRecord = RecordSelection(family: .hevc, quality: "High", resolution: .named(width: 3840, height: 2160), frameRate: 30, colour: .rec709)
    private static let placeholderPhoto = PhotoSelection(format: .heif, megapixels: 12)

    var mode: CaptureMode { didSet { selectionChanged() } }
    var record: RecordSelection { didSet { selectionChanged() } }
    var photo: PhotoSelection { didSet { selectionChanged() } }
    var sheet: CameraSheet?
    /// True at launch when the screen is the Library or the Editor; the Library is a full-screen cover.
    var isLibraryPresented: Bool
    var phase: CameraPhase
    var freeBytes: Int64
    /// Set only through `show(_:from:)` and cleared only through `clearNotice(from:)`, so each event clears only its own.
    private(set) var notice: String?
    private(set) var meterLevels: [Double] = []
    var lastCapture: URL?
    private(set) var capabilities: CaptureCapabilities
    private(set) var lensID: String { didSet { selectionChanged() } }
    var isRecording: Bool
    var recordingStart: Date?
    private(set) var access: CaptureAccess
    private(set) var pressureLevel: PressureLevel = .nominal
    private(set) var isThermalPressure = false
    /// True from any interruption, backgrounding included, until it ends or the session restarts. Kept apart from the
    /// notice, which an interruption does not always set.
    private(set) var isInterrupted = false
    /// True while the scanner sets formats on the cameras (first scan or rescan). Lens and mode cannot change then,
    /// and no configure is queued; the selection in force when the scan ends is configured afterwards.
    var isScanningFormats = false
    /// The camera's live values, polled while the session runs; shown only through `shownReadouts`.
    private(set) var readouts = LiveReadouts()
    /// The latest format sweep, kept after it ends so its result stays on screen.
    var sweep: FormatSweep?
    /// The saved looks, read at launch and whenever the Library closes.
    var looks: [Look] = []
    /// The look the camera applies; nil is None. Set by `CameraModel+Look`, and by `select(_:)` when a recovery returns to
    /// the default selection.
    var cameraLook: CameraLook?
    /// True when the look's frames could not be drawn with the current format; the viewfinder shows the plain preview until
    /// the next lens, mode, format or look change tries again. The look stays selected.
    var isLookViewfinderUnavailable = false
    /// True from the start of a sweep until the user's selection is back. Lens, mode, selection, capture, Record settings
    /// and rescans are all held meanwhile, and nothing is saved as the user's selection.
    var isSweeping = false
    /// Options that failed the last sweep of each lens on this OS build; loaded on the device only.
    var failedCombinations = FailedCombinations(osBuild: "", failedByLens: [:])
    /// Every clip a sweep started whose result has not arrived yet, by `CaptureStore.clipKey`; it stays a sweep clip
    /// whenever the result comes.
    @ObservationIgnored var sweepClips: Set<String> = []

    @ObservationIgnored private let defaults: UserDefaults
    /// `-keepSweepClips on` keeps each sweep clip; otherwise only its sidecar stays.
    @ObservationIgnored let keepsSweepClips: Bool
    @ObservationIgnored private let isScripted: Bool
    /// The Simulator keeps the stand-in free space; the device reads it.
    @ObservationIgnored private let isSimulator: Bool
    /// `-freeSpaceMarginMB N`: recording stops N MB before the volume is full, in place of the 2 GB reserve, to test that path.
    @ObservationIgnored let freeSpaceMarginMB: Int?
    @ObservationIgnored let capabilitySource: CapabilitySource
    /// Set by `attachSession` once the session has a working configuration; from then on selection changes reconfigure it.
    @ObservationIgnored var configurator: (any SessionConfigurator)?
    /// The tail of the serial configure chain; each task returns its configure error, or nil.
    @ObservationIgnored var configureTask: Task<CameraSessionError?, Never>?
    /// Bumped per requested configuration; a queued configure that is no longer the latest is skipped.
    @ObservationIgnored var configureGeneration = 0
    /// The configuration last sent to the chain, so an unchanged selection does not reconfigure.
    @ObservationIgnored var requestedConfiguration: SessionConfiguration?
    /// What the session last applied, and the selection that produced it; a failed configure returns to them.
    @ObservationIgnored var lastWorking: (configuration: SessionConfiguration, selection: SavedSelections)?
    /// The last configuration that ran for `confirmationDelay` with no runtime error, and its selection; a selection that
    /// stops the camera once running returns to it (`CameraModel+Recovery`).
    @ObservationIgnored var confirmed: (configuration: SessionConfiguration, selection: SavedSelections)?
    /// `runningConfirmation`, shortened by tests.
    @ObservationIgnored var confirmationDelay: Duration = CameraModel.runningConfirmation
    /// Waits `confirmationDelay` after a configuration starts running, then confirms it.
    @ObservationIgnored var confirmation: Task<Void, Never>?
    /// Counts the runtime errors handled by `cameraStopped`, so a confirmation or a recovery that a newer one overtook does nothing.
    @ObservationIgnored var runtimeErrorCount = 0
    /// True from an automatic recovery until a configuration is confirmed; another runtime error meanwhile ends in the
    /// stopped state, so recovery never loops.
    @ObservationIgnored var isRecoveryUnconfirmed = false
    /// The configuration rule 5 restarted automatically; it is not restarted automatically again until a user action
    /// (a selection change or Try again) clears it, so a configuration that keeps stopping cannot loop.
    @ObservationIgnored var autoRestarted: SessionConfiguration?
    /// True when a runtime error came during a recording or a sweep; the recovery runs once that ends.
    @ObservationIgnored var isRecoveryDeferred = false
    /// True from a media-services reset until its `.restarted`, a later runtime error that is not a reset, or the model's own
    /// next start of the session: the session restarts itself meanwhile, so the camera is not in the stopped state and nothing
    /// here starts it. Never set while the camera is released for the Library or held by a rescan, whose session is stopped on
    /// purpose and restarts nothing itself; their own configure and start bring it back.
    var isResettingMediaServices = false
    /// The mode a first launch picks, for the default selection.
    @ObservationIgnored let launchMode: CaptureMode
    /// True while several selection properties are set as one change (a restore or a capabilities load);
    /// the caller persists and reconfigures once at the end.
    @ObservationIgnored private var isApplyingSelection = false
    /// True from a launch without capabilities until real ones arrive; nothing is saved meanwhile.
    @ObservationIgnored private var isAwaitingRestore: Bool
    /// The running session, for capture; set by `start(session:)`.
    @ObservationIgnored var cameraSession: CameraSession?
    /// Injected so photos, recordings, sweeps and imports number files from one store; otherwise created on first use.
    @ObservationIgnored private var captureStore: CaptureStore?
    /// Photo captures still running, by file number. A configure queued after a press waits for them,
    /// because Bayer RAW needs the zoom unchanged until the capture ends (AVCapturePhotoOutput.h).
    @ObservationIgnored private var photoCaptures: [Int: Task<Void, Never>] = [:]
    /// The last photo capture pressed with a look; the next one with a look finishes after it.
    @ObservationIgnored private var lookFinishTail: Task<Void, Never>?
    /// The start of the recording in flight, so a stop pressed while it is still starting waits for it.
    @ObservationIgnored var recordingStartTask: Task<Void, Never>?
    /// The clip being recorded, from the press until its result; a stop or restart that finds no result coming ends it.
    @ObservationIgnored var recordingClip: (url: URL, option: VideoOption)?
    /// Clips the model ended without their result, by `CaptureStore.clipKey`; a result that still arrives changes no
    /// recording state.
    @ObservationIgnored var unreportedClips: Set<String> = []
    /// What put `notice` there; nil when no notice is shown.
    @ObservationIgnored var noticeSource: NoticeSource?
    /// False when the Library could not be built at launch; its item then says so instead of opening it.
    @ObservationIgnored let isLibraryAvailable: Bool
    /// The store shared with the Library and the editor; nil when none could be made, and the camera then has only None.
    @ObservationIgnored let lookStore: LookStore?
    /// True when Record settings opens scrolled to the Look row (a scripted launch with a look, for screenshots).
    @ObservationIgnored let scrollsToLookRow: Bool
    /// The tail of the serial chain that releases the camera for the Library and takes it back.
    @ObservationIgnored var libraryHandoff: Task<Void, Never>?
    /// True from the moment the session let go of its camera for the Library until it runs again.
    @ObservationIgnored var isCameraReleasedForLibrary = false
    /// Waits for the look's first frames after a configure; a stall falls back to the plain preview.
    @ObservationIgnored var frameWatch: Task<Void, Never>?
    /// True while a rescan holds the session stopped, until it runs again; no frame watch starts meanwhile.
    @ObservationIgnored var isSessionStoppedForRescan = false

    static let formatFailedNotice = "That format could not be used."
    static let formatSetupFailed = "This format could not be set up."
    init(config: LaunchConfig, capabilities: CaptureCapabilities, isSimulator: Bool, defaults: UserDefaults = .standard,
         capabilitySource: CapabilitySource = .device, captureStore: CaptureStore? = nil, isLibraryAvailable: Bool = true,
         lookStore: LookStore? = nil) {
        self.captureStore = captureStore
        self.lookStore = lookStore
        self.isLibraryAvailable = isLibraryAvailable
        self.capabilities = capabilities
        self.defaults = defaults
        self.capabilitySource = capabilitySource
        self.isScripted = config.isScripted
        self.isSimulator = isSimulator
        self.freeSpaceMarginMB = config.freeSpaceMarginMB
        self.keepsSweepClips = config.keepsSweepClips
        self.launchMode = config.mode
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
        case .library, .editor: self.sheet = nil
        }
        self.isLibraryPresented = config.screen == .library || config.screen == .editor

        let saved = config.isScripted ? nil : SavedSelections.load(from: defaults)
        let resolved = Self.resolve(lensID: saved?.lensID, record: saved?.record, photo: saved?.photo, in: capabilities)
        self.lensID = resolved.lensID
        self.mode = saved?.mode ?? config.mode
        self.record = resolved.record ?? Self.placeholderRecord
        self.photo = resolved.photo ?? Self.placeholderPhoto
        let looks = lookStore?.all() ?? []
        self.looks = looks
        if let name = config.cameraLookName {
            self.cameraLook = looks.first { $0.name == name }.map(CameraLook.init)
        } else {
            self.cameraLook = CameraLook.reconciled(saved?.look, with: looks)
        }
        self.scrollsToLookRow = config.screen == .record && config.cameraLookName != nil
        // A device launch starts with no capabilities, so the saved choices wait for real ones and must not be overwritten meanwhile.
        self.isAwaitingRestore = !config.isScripted && capabilities.lenses.isEmpty
        // A look the launch mode cannot take is None, with no notice.
        if !isLookOffered { self.cameraLook = nil }
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
        return SessionConfiguration.make(lens: currentLens, mode: mode, video: currentVideoOption, photo: currentPhotoOption, access: access,
                                         needsFrames: needsFrames)
    }

    /// The current options as the screen may name them: none while formats are being read, and none the device has not reported.
    /// Only a working camera, or the Simulator's labelled stand-in, names a format or a measurement.
    var hasCamera: Bool { phase == .ready || phase == .simulator }
    var shownVideoOption: VideoOption? { hasCamera ? currentVideoOption : nil }
    private var shownPhotoOption: PhotoOption? { hasCamera ? currentPhotoOption : nil }

    /// Levels only from a running session with a microphone; otherwise both bars read empty.
    var shownMeterLevels: [Double] {
        phase == .ready && access.recordsSound && meterLevels.count == 2 ? meterLevels : [0, 0]
    }

    var summaryParts: [String] {
        switch mode {
        case .video:
            guard let option = shownVideoOption else { return ["--"] }
            return [option.codec.family.title, option.resolution.label, option.colour.shortName] + (summaryLookName.map { [$0] } ?? [])
        case .photo:
            guard let option = shownPhotoOption else { return ["--"] }
            return [option.format.rawValue, option.label] + (summaryLookName.map { [$0] } ?? [])
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

    /// Record settings, and the format sweep from the summary's long press, open only once the device's formats are
    /// known and never while recording, so no control names a format the clip is not recording. A stopped camera keeps
    /// them, so another format can be chosen.
    var canOpenRecordSettings: Bool {
        (hasCamera || isCameraStopped) && !isRecording && !isSweeping && !(capabilities.videoOptions.isEmpty && capabilities.photoOptions.isEmpty)
    }

    func openRecordSettings() {
        guard canOpenRecordSettings else { return }
        sheet = .record
    }

    /// Audio meters and the remaining-time estimate describe video recording, so photo mode hides them.
    var showsVideoReadouts: Bool { mode == .video }

    /// Never while the Library covers the camera, whatever the phase says: a Camera Control press under it would capture
    /// something nobody can see.
    var canCapture: Bool {
        guard !isSweeping, !isLibraryPresented, StatusText.canRecord(phase: phase, mode: mode, minutesRemaining: minutesRemaining) else { return false }
        switch mode {
        case .video: return currentVideoOption != nil
        case .photo: return currentPhotoOption != nil
        }
    }

    /// The strip's Lens and Mode items follow this; `isScanningFormats` also keeps configures from queuing.
    var canChangeLensOrMode: Bool { !isRecording && !isScanningFormats && !isSweeping }

    func selectLens(_ id: String) {
        guard id != lensID, !isSweeping, capabilities.lenses.contains(where: { $0.id == id }) else { return }
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
    /// a photo or a new recording only when `canCapture`. During a sweep nothing is allowed, stopping included:
    /// the sweep starts and stops its own clips.
    private func perform(_ action: CaptureAction) {
        guard !isSweeping else { return }
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
        refreshLastCapture()
    }

    /// Reads the newest photo or clip again, so one deleted in the Library stops showing and an import counts.
    func refreshLastCapture() {
        if captureStore == nil {
            do throws(CaptureStoreError) {
                captureStore = try CaptureStore.appDefault()
            } catch {
                Self.logger.error("\(error.description, privacy: .public)")
                ErrorJournal.record(error.description)
                return
            }
        }
        lastCapture = captureStore?.latestCapture()
    }

    /// The captures folder, created on first use; nil, with `failureNotice` shown, when it cannot be.
    func store(failureNotice: String) -> CaptureStore? {
        if let captureStore { return captureStore }
        do throws(CaptureStoreError) {
            let store = try CaptureStore.appDefault()
            captureStore = store
            return store
        } catch {
            Self.logger.error("\(error.description, privacy: .public)")
            ErrorJournal.record(error.description)
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
        let look = cameraLook
        let format = option.format
        let edits = EditStore(directory: store.directory)
        // Captures with a look finish in press order, one bake at a time: each waits for the one pressed before it, so an
        // older photo never becomes the last capture after a newer one and 48 MP renders never overlap. Without a look the
        // chain is neither read nor extended.
        let earlierFinish = look != nil ? lookFinishTail : nil
        let capture = Task {
            defer { photoCaptures[sequence] = nil }
            _ = await pendingConfigure?.value
            let result: PhotoCaptureResult
            do throws(PhotoCaptureError) {
                result = try await cameraSession.capturePhoto(format: option.format, dngURL: dngURL, heicURL: heicURL)
            } catch {
                result = PhotoCaptureResult(saved: [], error: error)
            }
            // The photo is already on disk; the bake runs inside this task, so a configure or the Library waits for it,
            // and the last capture is set only after it, so the strip shows the baked picture.
            var lookNotice: String?
            if let look {
                await earlierFinish?.value
                lookNotice = await LookCapture.finish(result, look: look, format: format, heicURL: heicURL, dngURL: dngURL, edits: edits).notice
            }
            photoFinished(requested: requested, result: result, lookNotice: lookNotice)
        }
        photoCaptures[sequence] = capture
        if look != nil { lookFinishTail = capture }
    }

    /// The notice always describes the latest capture: a full save clears an earlier photo notice. The save report's
    /// notice wins over the look's. Internal so tests can deliver a result without a session.
    func photoFinished(requested: [URL], result: PhotoCaptureResult, lookNotice: String? = nil) {
        if let error = result.error {
            Self.logger.error("\(error.description, privacy: .public)")
            ErrorJournal.record(error.description)
        }
        let report = PhotoSaveReport.make(requested: requested, saved: result.saved, error: result.error)
        if let saved = report.lastCapture { lastCapture = saved }
        // A full save replaces an earlier capture notice with none.
        if let notice = report.notice ?? lookNotice {
            show(notice, from: .capture)
        } else {
            clearNotice(from: .capture)
        }
        refreshFreeBytes()
    }

    /// The Simulator keeps its stand-in figure.
    func refreshFreeBytes() {
        guard !isSimulator else { return }
        freeBytes = FreeSpace.availableBytes()
    }

    /// Waits for every photo capture already running.
    func waitForPhotoCaptures() async {
        await Self.waitForAll(Array(photoCaptures.values))
    }

    /// Waits for `captures`, taken when the caller queued its work: a capture started later may itself be waiting on
    /// that work.
    private static func waitForAll(_ captures: [Task<Void, Never>]) async {
        for capture in captures {
            await capture.value
        }
    }

    private func settleSelections() {
        record = Self.settle(record, with: recordResolver) ?? record
        photo = Self.settle(photo, with: photoResolver) ?? photo
    }

    var currentSelection: SavedSelections {
        SavedSelections(mode: mode, lensID: lensID, record: record, photo: photo, look: cameraLook)
    }

    func selectionChanged() {
        guard !isApplyingSelection else { return }
        // A selection change is a user action: it gives the automatic restart back.
        autoRestarted = nil
        // A new lens, mode, format or look tries the viewfinder again.
        isLookViewfinderUnavailable = false
        clearNotice(from: .look)
        settleLook()
        persist()
        enqueueConfigure()
    }

    /// A sweep's options are never saved as the user's selection.
    func persist() {
        guard !isScripted, !isAwaitingRestore, !isSweeping else { return }
        currentSelection.save(to: defaults)
    }

    /// Hands the model a session already running `configuration`, which was built from `selection`;
    /// later selection changes reconfigure it. The caller arms its confirmation once the session's start has returned.
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
    func enqueueConfigure() -> Task<CameraSessionError?, Never>? {
        guard !isScanningFormats, !isRecording, !isHeldForLibrary, let configurator, let configuration = sessionConfiguration,
              configuration != requestedConfiguration else { return nil }
        requestedConfiguration = configuration
        configureGeneration += 1
        let generation = configureGeneration
        let selection = currentSelection
        let previous = configureTask
        let captures = Array(photoCaptures.values)
        let task = Task { () -> CameraSessionError? in
            _ = await previous?.value
            await Self.waitForAll(captures)
            guard generation == configureGeneration else { return nil }
            // Read before the configure and start, so an error handled while they are awaited still stops the confirmation.
            let errors = runtimeErrorCount
            do throws(CameraSessionError) {
                try await configurator.configure(configuration)
            } catch {
                configureFailed(error, generation: generation)
                return error
            }
            lastWorking = (configuration, selection)
            clearNotice(from: .configuration)
            // A stopped camera runs again with the new selection; a running one is confirmed once it has run long enough.
            if await startIfStopped(configurator) || phase == .ready {
                confirmWhenRunning(configuration, since: errors)
            }
            watchFrames(for: configuration)
            return nil
        }
        configureTask = task
        return task
    }

    /// The session has already restored its last working configuration; the selection follows it,
    /// unless a newer selection is queued, which then stands.
    private func configureFailed(_ error: CameraSessionError, generation: Int) {
        Self.logger.error("\(error.description, privacy: .public)")
        ErrorJournal.record(error.description)
        guard let lastWorking else {
            phase = .failed(Self.formatSetupFailed)
            return
        }
        show(Self.formatFailedNotice, from: .configuration)
        guard generation == configureGeneration else { return }
        restore(lastWorking)
        configureTask = nil
        // The failed configure moved the chain on, which drops a pending confirmation; the session still runs the restored
        // configuration, so it is timed again. A sweep option is never confirmed.
        if phase == .ready, !isSweeping { confirmWhenRunning(lastWorking.configuration, since: runtimeErrorCount) }
    }

    /// Puts back `working`'s lens, mode, record and photo as one change, as the session now runs it, and saves them.
    /// Nothing is queued: `requestedConfiguration` becomes `working`'s configuration.
    func restore(_ working: (configuration: SessionConfiguration, selection: SavedSelections)) {
        isApplyingSelection = true
        lensID = working.selection.lensID
        mode = working.selection.mode
        record = working.selection.record
        photo = working.selection.photo
        isApplyingSelection = false
        settleLook()
        // The selection change reset the viewfinder's fallback; the session is back on a configuration that may have no
        // frames (an earlier fallback), so the viewfinder follows what was restored, not what was asked for.
        isLookViewfinderUnavailable = cameraLook != nil && !working.configuration.needsFrames
        requestedConfiguration = working.configuration
        persist()
    }

    /// What a first launch picks: the launch mode, the default lens, its default record and photo selections, no look.
    /// Nil without a lens.
    var defaultSelection: SavedSelections? {
        let resolved = Self.resolve(lensID: nil, record: nil, photo: nil, in: capabilities)
        guard !resolved.lensID.isEmpty else { return nil }
        return SavedSelections(mode: launchMode, lensID: resolved.lensID, record: resolved.record ?? record,
                               photo: resolved.photo ?? photo, look: nil)
    }

    /// Selects `selection` as one change and saves it; nothing is queued.
    func select(_ selection: SavedSelections) {
        isApplyingSelection = true
        lensID = selection.lensID
        mode = selection.mode
        record = selection.record
        photo = selection.photo
        cameraLook = selection.look
        isApplyingSelection = false
        isLookViewfinderUnavailable = false
        settleLook()
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
        failedCombinations = FailedCombinations.load(directory: capabilitySource.cacheDirectory, osBuild: DeviceIdentity.osBuild())
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
        // Read before the configure and start, so an error handled while they are awaited is not lost.
        let errors = runtimeErrorCount
        do {
            try await session.configure(configuration)
        } catch {
            Self.logger.error("\(error.description, privacy: .public)")
            ErrorJournal.record(error.description)
            phase = .failed(Self.formatSetupFailed)
            return
        }
        attachSession(session, configuredWith: configuration, selection: selection)
        cameraSession = session
        await session.start()
        isResettingMediaServices = false
        watchFrames(for: configuration)
        phase = .ready
        // Timed only once the start has returned, so a slow start never drops it, and for whatever the session last applied:
        // a selection changed during the first configure was applied by the chain before the phase was ready, so it armed
        // nothing itself. One the chain has still to apply arms its own once it has.
        if let lastWorking { confirmWhenRunning(lastWorking.configuration, since: errors) }
        releaseIfLibraryOpen()
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

    /// Ten times a second; the levels stay empty without a microphone.
    /// While recording, free space is read again about once a second, so the remaining time counts down during a clip.
    private func pollMeters(of session: CameraSession) async {
        var tick = 0
        while !Task.isCancelled {
            let levels = await session.audioLevels()
            if levels != meterLevels { meterLevels = levels }
            tick = (tick + 1) % 10
            if isRecording, tick == 0 { refreshFreeBytes() }
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

    func show(_ text: String, from source: NoticeSource) {
        notice = text
        noticeSource = source
    }

    /// Clears the notice only when `source` put it there.
    func clearNotice(from source: NoticeSource) {
        guard noticeSource == source else { return }
        notice = nil
        noticeSource = nil
    }

    func apply(_ event: SessionEvent) {
        switch event {
        case .interrupted(let reason):
            isInterrupted = true
            // An interruption without a notice (backgrounding) changes nothing; one with a notice never covers a capture notice.
            if let interruptionNotice = reason.notice, noticeSource != .capture {
                show(interruptionNotice, from: .interruption)
            }
        case .interruptionEnded:
            isInterrupted = false
            clearNotice(from: .interruption)
            rewatchFrames()
        case .runtimeError(let message) where Self.isMediaServicesReset(message):
            // Sets no notice; the phase says the camera stopped. The session restarts itself and `.restarted` follows, so no
            // pending confirmation may mark the camera ready and nothing here starts it meanwhile.
            Self.logger.error("\(message, privacy: .public)")
            ErrorJournal.record(message)
            runtimeErrorCount += 1
            confirmation?.cancel()
            confirmation = nil
            // Released for the Library or held by a rescan, the session is stopped on purpose and that flow's own configure
            // and start bring it back, so the phase stays as it is.
            guard phase != .released, !isCameraReleasedForLibrary, !isScanningFormats, !isSessionStoppedForRescan else { break }
            isResettingMediaServices = true
            phase = .failed(Self.cameraStopped)
        case .runtimeError(let message):
            cameraStopped(message)
        case .restarted:
            isResettingMediaServices = false
            // The session runs again, so a pause notice is stale; any other notice stays. A clip recording before the
            // reset is gone, and the movie output may never report it. With the Library open the camera ends released, a
            // release queued whatever the phase was (one that already ran makes the queued one do nothing). With the Library
            // closed after a failed return the session holds no camera, so the failed state stands until the next close
            // retries.
            // A rescan holds the session stopped and ends by configuring and starting it itself, so the phase is its own.
            if !isScanningFormats, !isSessionStoppedForRescan, !isCameraReleasedForLibrary || isLibraryPresented {
                phase = .ready
                releaseIfLibraryOpen()
            }
            isInterrupted = false
            clearNotice(from: .interruption)
            endRecordingWithoutResult(clip: nil, context: "restarted")
            rewatchFrames()
        case .microphoneUnavailable(let message):
            // Reads the same as microphone denied: video still records, without sound.
            Self.logger.error("\(message, privacy: .public)")
            ErrorJournal.record(message)
            access.microphone = .denied
        case .pressure(let level, let isThermal):
            pressureLevel = level
            isThermalPressure = isThermal
        case .framesUnavailable:
            framesUnavailable()
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
