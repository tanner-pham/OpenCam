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
    var notice: String?
    var meterLevels: [Double] = [0.62, 0.54]
    var lastCapture: URL?
    private(set) var capabilities: CaptureCapabilities
    private(set) var lensID: String { didSet { selectionChanged() } }
    private(set) var isRecording: Bool
    private(set) var recordingStart: Date?
    private(set) var access: CaptureAccess
    private(set) var pressureLevel: PressureLevel = .nominal
    private(set) var isThermalPressure = false

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let isScripted: Bool
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
    /// True while a failed configure puts the last working selection back, so those changes do not reconfigure.
    @ObservationIgnored private var isRestoringSelection = false

    static let formatFailedNotice = "That format could not be used."

    init(config: LaunchConfig, capabilities: CaptureCapabilities, isSimulator: Bool, defaults: UserDefaults = .standard) {
        self.capabilities = capabilities
        self.defaults = defaults
        self.isScripted = config.isScripted
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
        let defaultID = Self.defaultLens(in: capabilities)?.id ?? ""
        let lensID = saved.map { saved in capabilities.lenses.contains { $0.id == saved.lensID } ? saved.lensID : defaultID } ?? defaultID
        self.lensID = lensID
        self.mode = saved?.mode ?? config.mode

        let lens = capabilities.lenses.first { $0.id == lensID }
        let recordResolver = RecordSelectionResolver(options: capabilities.videoOptions, lens: lens)
        let photoResolver = PhotoSelectionResolver(options: capabilities.photoOptions, lenses: capabilities.lenses, lensID: lensID)
        self.record = Self.settle(saved?.record, with: recordResolver) ?? Self.placeholderRecord
        self.photo = Self.settle(saved?.photo, with: photoResolver) ?? Self.placeholderPhoto
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
        return SessionConfiguration(lens: currentLens, mode: mode, video: currentVideoOption, photo: currentPhotoOption,
                                    includesAudio: access.recordsSound)
    }

    /// The current options as the screen may name them: none while formats are being read, and none the device has not reported.
    private var shownVideoOption: VideoOption? { phase == .scanning ? nil : currentVideoOption }
    private var shownPhotoOption: PhotoOption? { phase == .scanning ? nil : currentPhotoOption }

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

    var remainingText: String {
        guard let option = shownVideoOption else { return "-- min" }
        return "\(DataRateEstimator.minutesRemaining(freeBytes: freeBytes, option: option)) min"
    }

    /// Record settings opens only once the device's formats are known.
    var canOpenRecordSettings: Bool {
        phase != .scanning && !(capabilities.videoOptions.isEmpty && capabilities.photoOptions.isEmpty)
    }

    func openRecordSettings() {
        guard canOpenRecordSettings else { return }
        sheet = .record
    }

    /// Audio meters and the remaining-time estimate describe video recording, so photo mode hides them.
    var showsVideoReadouts: Bool { mode == .video }

    var canCapture: Bool {
        guard phase == .ready else { return false }
        switch mode {
        case .video: return currentVideoOption != nil
        case .photo: return currentPhotoOption != nil
        }
    }

    func selectLens(_ id: String) {
        guard id != lensID, capabilities.lenses.contains(where: { $0.id == id }) else { return }
        lensID = id
        settleSelections()
    }

    func replaceCapabilities(_ capabilities: CaptureCapabilities) {
        self.capabilities = capabilities
        if !capabilities.lenses.contains(where: { $0.id == lensID }) {
            lensID = Self.defaultLens(in: capabilities)?.id ?? ""
        }
        settleSelections()
    }

    func capturePressed() {}

    private func settleSelections() {
        record = Self.settle(record, with: recordResolver) ?? record
        photo = Self.settle(photo, with: photoResolver) ?? photo
    }

    private var currentSelection: SavedSelections {
        SavedSelections(mode: mode, lensID: lensID, record: record, photo: photo)
    }

    private func selectionChanged() {
        persist()
        guard !isRestoringSelection else { return }
        enqueueConfigure()
    }

    private func persist() {
        guard !isScripted else { return }
        currentSelection.save(to: defaults)
    }

    /// Hands the model a session already running `configuration`; later selection changes reconfigure it.
    func attachSession(_ configurator: any SessionConfigurator, configuredWith configuration: SessionConfiguration) {
        self.configurator = configurator
        requestedConfiguration = configuration
        lastWorking = (configuration, currentSelection)
    }

    /// Applies the current selection behind any configure already queued, and throws if it could not be used.
    /// After a failure the session, the selection and `phase` stay as they were before, and `notice` says so.
    func applySelection() async throws(CameraSessionError) {
        guard let task = enqueueConfigure() ?? configureTask else { return }
        if let error = await task.value { throw error }
    }

    /// Queues a configure behind any running one. A lens switch changes lens, record and photo in one turn;
    /// only the last of those runs, because the earlier ones are superseded before the chain reaches them.
    @discardableResult
    private func enqueueConfigure() -> Task<CameraSessionError?, Never>? {
        guard let configurator, let configuration = sessionConfiguration, configuration != requestedConfiguration else { return nil }
        requestedConfiguration = configuration
        configureGeneration += 1
        let generation = configureGeneration
        let selection = currentSelection
        let previous = configureTask
        let task = Task { () -> CameraSessionError? in
            _ = await previous?.value
            guard generation == configureGeneration else { return nil }
            do throws(CameraSessionError) {
                try await configurator.configure(configuration)
            } catch {
                configureFailed(error, generation: generation)
                return error
            }
            lastWorking = (configuration, selection)
            if notice == Self.formatFailedNotice { notice = nil }
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
            phase = .failed("The camera could not start.")
            return
        }
        notice = Self.formatFailedNotice
        guard generation == configureGeneration else { return }
        isRestoringSelection = true
        lensID = lastWorking.selection.lensID
        mode = lastWorking.selection.mode
        record = lastWorking.selection.record
        photo = lastWorking.selection.photo
        isRestoringSelection = false
        requestedConfiguration = lastWorking.configuration
        configureTask = nil
    }

    private static func defaultLens(in capabilities: CaptureCapabilities) -> Lens? {
        capabilities.lenses.first { $0.kind == .wide && $0.zoomFactor == 1 } ?? capabilities.lenses.first
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
        access = await CameraSession.requestAccess()
        guard access.canUseCamera else {
            phase = access.camera == .restricted ? .cameraRestricted : .cameraDenied
            return
        }
        let lenses = LensDiscovery.lenses()
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
        do {
            try await session.configure(configuration)
        } catch {
            Self.logger.error("\(error.description, privacy: .public)")
            phase = .failed("The camera could not start.")
            return
        }
        attachSession(session, configuredWith: configuration)
        await session.start()
        phase = .ready
        for await event in session.events {
            apply(event)
        }
    }

    /// Uses the cached capabilities when they were written on this OS build and model for the same cameras;
    /// otherwise scans, saves to the cache and leaves a copy in Documents for comparison with the probe report.
    func loadCapabilities(lenses: [Lens]) async {
        let osBuild = DeviceIdentity.osBuild(), modelIdentifier = DeviceIdentity.modelIdentifier()
        let cache = CapabilityCache(directory: URL.applicationSupportDirectory.appending(path: "OpenCam"))
        if let cached = cache.load(osBuild: osBuild, modelIdentifier: modelIdentifier) {
            // The cache may lack lenses the scan skipped. Lens labels can carry localized device names,
            // so the freshly discovered lenses are kept for the cached ids.
            let cachedIDs = Set(cached.lenses.map(\.id))
            let current = lenses.filter { cachedIDs.contains($0.id) }
            if !current.isEmpty, current.count == cachedIDs.count {
                replaceCapabilities(CaptureCapabilities(lenses: current, videoOptions: cached.videoOptions, photoOptions: cached.photoOptions,
                                                        osBuild: osBuild, modelIdentifier: modelIdentifier))
                return
            }
        }
        phase = .scanning
        let formats: [FormatDescriptor]
        do {
            formats = try await CapabilityScanner.scan(lenses: lenses)
        } catch {
            Self.logger.error("\(error.description, privacy: .public)")
            phase = .failed("The camera could not start.")
            return
        }
        let capabilities = CapabilityMapper.capabilities(lenses: lenses, formats: formats, osBuild: osBuild, modelIdentifier: modelIdentifier)
        guard !capabilities.lenses.isEmpty else {
            Self.logger.error("[CameraModel:loadCapabilities] No camera reported a usable format — {lenses: \(lenses.count), formats: \(formats.count)}")
            phase = .failed("The camera could not start.")
            return
        }
        replaceCapabilities(capabilities)
        for directory in [cache.directory, URL.documentsDirectory] {
            do {
                try CapabilityCache(directory: directory).save(capabilities)
            } catch {
                Self.logger.error("\(error.description, privacy: .public)")
            }
        }
    }

    func apply(_ event: SessionEvent) {
        switch event {
        case .interrupted(let reason):
            notice = reason.notice
        case .interruptionEnded:
            notice = nil
        case .runtimeError(let message):
            Self.logger.error("\(message, privacy: .public)")
            phase = .failed("The camera stopped.")
        case .restarted:
            phase = .ready
            notice = nil
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
