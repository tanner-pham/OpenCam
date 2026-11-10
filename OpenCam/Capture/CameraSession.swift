import AVFoundation
import OSLog

/// Owns `AVCaptureSession` and every device it touches, on its own serial queue.
actor CameraSession: SessionConfigurator {
    nonisolated let previewSource: PreviewSource
    nonisolated let events: AsyncStream<SessionEvent>
    /// Backs `recordings`: one result per finished clip, yielded by the recorder.
    nonisolated let recordingResults: AsyncStream<RecordingResult>

    private let queue = DispatchSerialQueue(label: "opencam.session")
    private let session: AVCaptureSession
    private let continuation: AsyncStream<SessionEvent>.Continuation
    private let recordingContinuation: AsyncStream<RecordingResult>.Continuation
    /// Its output is attached in video mode only.
    private let recorder: MovieRecorder
    /// Registered on the first `start()`, because the runtime-error observer needs a reference to this actor.
    private var notificationTokens: [any NSObjectProtocol] = []
    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    /// Its output is attached in photo mode only.
    private let photoCapturer = PhotoCapturer()
    private var pressureObservation: NSKeyValueObservation?
    /// True from a media-services-reset restart until it succeeds, so a reset during that restart is not retried.
    private var isRestartingAfterReset = false
    /// Restored when a later configure fails.
    private var lastWorkingConfiguration: SessionConfiguration?
    /// The white-balance mode a ProRes RAW recording replaced, restored when that recording finishes.
    private var whiteBalanceRestore: (device: AVCaptureDevice, mode: AVCaptureDevice.WhiteBalanceMode)?
    /// Held here because the session does not keep its controls delegate alive.
    private let controlsDelegate = CameraControlsDelegate()
    private static let logger = Logger(subsystem: "local.opencam.app", category: "CameraSession")

    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    init() {
        let session = AVCaptureSession()
        // activeColorSpace is chosen per option; the session would otherwise override it.
        session.automaticallyConfiguresCaptureDeviceForWideColor = false
        let (events, continuation) = AsyncStream.makeStream(of: SessionEvent.self)
        let (recordingResults, recordingContinuation) = AsyncStream.makeStream(of: RecordingResult.self)
        self.session = session
        self.previewSource = PreviewSource(session: session)
        self.events = events
        self.continuation = continuation
        self.recordingResults = recordingResults
        self.recordingContinuation = recordingContinuation
        self.recorder = MovieRecorder(results: recordingContinuation)
    }

    isolated deinit {
        for token in notificationTokens {
            NotificationCenter.default.removeObserver(token)
        }
        continuation.finish()
        recordingContinuation.finish()
    }

    /// Asks for the camera, then the microphone. The microphone is only asked for once the camera is allowed.
    nonisolated static func requestAccess() async -> CaptureAccess {
        var camera = AccessState(AVCaptureDevice.authorizationStatus(for: .video))
        if camera == .notDetermined {
            camera = await AVCaptureDevice.requestAccess(for: .video) ? .authorized : .denied
        }
        var microphone = AccessState(AVCaptureDevice.authorizationStatus(for: .audio))
        if camera == .authorized, microphone == .notDetermined {
            microphone = await AVCaptureDevice.requestAccess(for: .audio) ? .authorized : .denied
        }
        return CaptureAccess(camera: camera, microphone: microphone)
    }

    /// On failure the last configuration that worked is applied again, so the session keeps running as it was,
    /// and the original error is thrown. If that restore fails too, a runtime error is reported.
    /// Refused while recording, because changing the format or outputs ends the clip.
    /// The Camera Control's system controls are installed last, for the device and mode now applied.
    func configure(_ configuration: SessionConfiguration) throws(CameraSessionError) {
        guard !recorder.output.isRecording else { throw .recordingInProgress }
        do throws(CameraSessionError) {
            try apply(configuration)
            lastWorkingConfiguration = configuration
            installSystemControls(CameraControlPlan.kinds(supportsControls: session.supportsControls, mode: configuration.mode, photoFormat: configuration.photo?.format ?? .heif))
        } catch {
            if let lastWorkingConfiguration, lastWorkingConfiguration != configuration {
                do {
                    try apply(lastWorkingConfiguration)
                    installSystemControls(CameraControlPlan.kinds(supportsControls: session.supportsControls, mode: lastWorkingConfiguration.mode, photoFormat: lastWorkingConfiguration.photo?.format ?? .heif))
                } catch let restoreError {
                    // The attached camera is unknown now, so no control may stay bound to the previous one.
                    installSystemControls([])
                    continuation.yield(.runtimeError("[CameraSession:configure] Cannot restore the last configuration — {lens: \(lastWorkingConfiguration.lens.id), error: \(restoreError)}"))
                }
            }
            throw error
        }
    }

    private func apply(_ configuration: SessionConfiguration) throws(CameraSessionError) {
        let lens = configuration.lens
        guard let device = AVCaptureDevice(uniqueID: lens.deviceUniqueID) else {
            throw .deviceMissing(lensID: lens.id)
        }
        // Declared first so it runs after the commit below, also when configuring throws and the old input is restored.
        defer { NotificationCenter.default.post(name: PreviewSource.didConfigureNotification, object: session) }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        // Input priority: the device's activeFormat dictates quality, and the session never changes it
        // (AVCaptureSessionPreset.h, AVCaptureSessionPresetInputPriority).
        if session.canSetSessionPreset(.inputPriority) {
            session.sessionPreset = .inputPriority
        }
        try attachVideo(device, lensID: lens.id)
        attachAudio(configuration.includesAudio)
        try attachPhotoOutput(configuration.mode == .photo)
        try attachMovieOutput(configuration.mode == .video)
        try applyFormat(configuration, to: device)
        if configuration.mode == .photo {
            try applyPhotoDimensions(configuration.photo, format: device.activeFormat)
        }
        pressureObservation = Self.observePressure(of: device, continuation: continuation)
    }

    func start() {
        if notificationTokens.isEmpty {
            notificationTokens = Self.observeNotifications(of: session, owner: self, continuation: continuation)
        }
        guard !session.isRunning else { return }
        session.startRunning()
        if session.isRunning { isRestartingAfterReset = false }
    }

    /// After `AVError.Code.mediaServicesWereReset` the session is restarted once; `.restarted` follows when it runs again.
    private func restartAfterMediaServicesReset() {
        guard !isRestartingAfterReset else { return }
        isRestartingAfterReset = true
        session.startRunning()
        guard session.isRunning else { return }
        isRestartingAfterReset = false
        continuation.yield(.restarted)
    }

    func stop() {
        guard session.isRunning else { return }
        session.stopRunning()
    }

    // MARK: Inputs

    private func attachVideo(_ device: AVCaptureDevice, lensID: String) throws(CameraSessionError) {
        if let videoInput, videoInput.device.uniqueID == device.uniqueID { return }
        let previous = videoInput
        if let previous { session.removeInput(previous) }
        guard let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
            if let previous, session.canAddInput(previous) { session.addInput(previous) }
            throw .cannotAddInput(lensID: lensID)
        }
        session.addInput(input)
        videoInput = input
    }

    /// A microphone that cannot attach never stops video: the session continues without sound and says so.
    private func attachAudio(_ includesAudio: Bool) {
        guard includesAudio else {
            if let audioInput { session.removeInput(audioInput) }
            audioInput = nil
            return
        }
        guard audioInput == nil else { return }
        guard let microphone = AVCaptureDevice.default(for: .audio) else {
            continuation.yield(.microphoneUnavailable("[CameraSession:configure] Microphone not found — {device: default audio}"))
            return
        }
        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: microphone)
        } catch {
            continuation.yield(.microphoneUnavailable("[CameraSession:configure] Cannot open the microphone — {device: \(microphone.localizedName), error: \(error)}"))
            return
        }
        guard session.canAddInput(input) else {
            continuation.yield(.microphoneUnavailable("[CameraSession:configure] Cannot add input — {lens: microphone}"))
            return
        }
        session.addInput(input)
        audioInput = input
    }

    // MARK: Outputs

    /// Photo capture is unsupported in Apple Log, which video mode may select, so the output is detached there.
    private func attachPhotoOutput(_ isAttached: Bool) throws(CameraSessionError) {
        let output = photoCapturer.output
        guard session.outputs.contains(output) != isAttached else { return }
        guard isAttached else {
            session.removeOutput(output)
            return
        }
        guard session.canAddOutput(output) else { throw .cannotAddOutput(name: "photo") }
        session.addOutput(output)
    }

    /// The movie output records video mode only; the microphone, when attached, connects to it automatically.
    private func attachMovieOutput(_ isAttached: Bool) throws(CameraSessionError) {
        let output = recorder.output
        guard session.outputs.contains(output) != isAttached else { return }
        guard isAttached else {
            session.removeOutput(output)
            return
        }
        guard session.canAddOutput(output) else { throw .cannotAddOutput(name: "movie") }
        session.addOutput(output)
    }

    /// The largest photo follows the selected size; it must be one the active format lists (AVCapturePhotoOutput.h,
    /// `maxPhotoDimensions`), and is set before the session starts on the first configure.
    private func applyPhotoDimensions(_ option: PhotoOption?, format: AVCaptureDevice.Format) throws(CameraSessionError) {
        guard let option else { return }
        guard let dimensions = format.supportedMaxPhotoDimensions.first(where: { Int($0.width) == option.width && Int($0.height) == option.height }) else {
            throw .noMatchingFormat(option: "\(option.format.rawValue) \(option.width) x \(option.height)")
        }
        let current = photoCapturer.output.maxPhotoDimensions
        guard current.width != dimensions.width || current.height != dimensions.height else { return }
        photoCapturer.output.maxPhotoDimensions = dimensions
    }

    // MARK: Format

    private func applyFormat(_ configuration: SessionConfiguration, to device: AVCaptureDevice) throws(CameraSessionError) {
        do {
            try device.lockForConfiguration()
        } catch {
            throw .lockFailed(reason: String(describing: error))
        }
        defer { device.unlockForConfiguration() }

        let zoom = CGFloat(configuration.lens.zoomFactor)
        switch configuration.mode {
        case .video:
            if let option = configuration.video {
                try applyVideo(option, zoom: zoom, to: device)
            }
        case .photo:
            try applyPhoto(configuration.photo, zoom: zoom, to: device)
        }
        guard zoom <= device.activeFormat.videoMaxZoomFactor else {
            throw .noMatchingFormat(option: "zoom \(configuration.lens.label)")
        }
        device.videoZoomFactor = zoom
    }

    /// Caller holds the configuration lock.
    private func applyVideo(_ option: VideoOption, zoom: CGFloat, to device: AVCaptureDevice) throws(CameraSessionError) {
        let space = Self.colorSpace(for: option.colour)
        let rate = Double(option.frameRate)
        let candidates = device.formats.compactMap { format -> (AVCaptureDevice.Format, AVFrameRateRange)? in
            let dimensions = format.formatDescription.dimensions
            guard Int(dimensions.width) == option.resolution.width, Int(dimensions.height) == option.resolution.height,
                  format.supportedColorSpaces.contains(space), zoom <= format.videoMaxZoomFactor,
                  let range = format.videoSupportedFrameRateRanges.first(where: { Self.range($0, contains: rate) })
            else { return nil }
            return (format, range)
        }
        guard let (format, range) = candidates.first(where: { !$0.0.isVideoBinned }) ?? candidates.first else {
            throw .noMatchingFormat(option: "\(option.resolution.detail) \(option.frameRate) fps \(option.colour.rawValue)")
        }
        device.activeFormat = format
        device.activeColorSpace = space
        let duration = Self.frameDuration(rate: option.frameRate, within: range)
        device.activeVideoMinFrameDuration = duration
        device.activeVideoMaxFrameDuration = duration
    }

    /// Photo capture is unsupported in Apple Log, so photo mode takes P3 when offered, else Rec. 709.
    /// Caller holds the configuration lock.
    private func applyPhoto(_ option: PhotoOption?, zoom: CGFloat, to device: AVCaptureDevice) throws(CameraSessionError) {
        if let option {
            let candidates = device.formats.filter { format in
                zoom <= format.videoMaxZoomFactor && format.supportedMaxPhotoDimensions.contains {
                    Int($0.width) == option.width && Int($0.height) == option.height
                }
            }
            let preferred = candidates.first { !$0.isVideoBinned && $0.supportedColorSpaces.contains(.P3_D65) }
                ?? candidates.first { !$0.isVideoBinned }
                ?? candidates.first
            guard let format = preferred else {
                throw .noMatchingFormat(option: "\(option.format.rawValue) \(option.width) x \(option.height)")
            }
            device.activeFormat = format
        }
        let spaces = device.activeFormat.supportedColorSpaces
        if spaces.contains(.P3_D65) {
            device.activeColorSpace = .P3_D65
        } else if spaces.contains(.sRGB) {
            device.activeColorSpace = .sRGB
        } else {
            throw .noMatchingFormat(option: "photo colour")
        }
        device.activeVideoMinFrameDuration = .invalid
        device.activeVideoMaxFrameDuration = .invalid
    }

    private static func colorSpace(for colour: ColourMode) -> AVCaptureColorSpace {
        switch colour {
        case .rec709: .sRGB
        case .p3: .P3_D65
        case .hlg: .HLG_BT2020
        case .appleLog: .appleLog
        case .appleLog2: .appleLog2
        }
    }

    /// The same 0.05 tolerance `StandardFrameRates.collapse` uses, so every offered rate finds its range.
    private static func range(_ range: AVFrameRateRange, contains rate: Double) -> Bool {
        range.minFrameRate - 0.05 <= rate && rate <= range.maxFrameRate + 0.05
    }

    /// 1/rate, clamped to the range so a 30 offered from a 29.97 maximum never sets an unsupported duration.
    private static func frameDuration(rate: Int, within range: AVFrameRateRange) -> CMTime {
        let rateValue = Double(rate)
        if rateValue > range.maxFrameRate { return range.minFrameDuration }
        if rateValue < range.minFrameRate { return range.maxFrameDuration }
        return CMTime(value: 1, timescale: CMTimeScale(rate))
    }

    // MARK: Events

    private nonisolated static func observeNotifications(
        of session: AVCaptureSession, owner: CameraSession, continuation: AsyncStream<SessionEvent>.Continuation
    ) -> [any NSObjectProtocol] {
        let center = NotificationCenter.default
        let interrupted = center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: nil) { notification in
            let rawReason = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int ?? 0
            continuation.yield(.interrupted(InterruptionReason(avReason: rawReason)))
        }
        let ended = center.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: nil) { _ in
            continuation.yield(.interruptionEnded)
        }
        let runtimeError = center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil) { [weak owner] notification in
            let error = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError
            let detail = error.map { "domain: \($0.domain), code: \($0.code), \($0.localizedDescription)" } ?? "no error"
            continuation.yield(.runtimeError("[CameraSession:runtimeError] Session stopped — {\(detail)}"))
            // AVError.h: AVErrorMediaServicesWereReset (-11819) in AVFoundationErrorDomain.
            if let error, error.domain == AVFoundationErrorDomain, error.code == AVError.Code.mediaServicesWereReset.rawValue {
                Task { await owner?.restartAfterMediaServicesReset() }
            }
        }
        return [interrupted, ended, runtimeError]
    }

    private nonisolated static func observePressure(
        of device: AVCaptureDevice, continuation: AsyncStream<SessionEvent>.Continuation
    ) -> NSKeyValueObservation {
        device.observe(\.systemPressureState, options: [.initial, .new]) { device, _ in
            let state = device.systemPressureState
            let isThermal = state.factors.contains(.systemTemperature) || state.factors.contains(.cameraTemperature)
            continuation.yield(.pressure(pressureLevel(state.level), isThermal: isThermal))
        }
    }

    private nonisolated static func pressureLevel(_ level: AVCaptureDevice.SystemPressureState.Level) -> PressureLevel {
        switch level {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        case .shutdown: .shutdown
        default: .nominal
        }
    }
}

extension CameraSession {
    /// Captures one photo in `format`; RAW goes to `dngURL` and HEIF to `heicURL`. Throws when the request cannot be made;
    /// once made, the result carries the files written and any error.
    func capturePhoto(format: PhotoFormat, dngURL: URL, heicURL: URL) async throws(PhotoCaptureError) -> PhotoCaptureResult {
        guard let device = videoInput?.device, session.outputs.contains(photoCapturer.output) else {
            throw .captureFailed(reason: "photo output not attached")
        }
        // Each request asks for the output's maximum, which must be a size the active format lists.
        let maximum = photoCapturer.output.maxPhotoDimensions
        guard device.activeFormat.supportedMaxPhotoDimensions.contains(where: { $0.width == maximum.width && $0.height == maximum.height }) else {
            throw .captureFailed(reason: "photo size \(maximum.width) x \(maximum.height) not offered by the active format")
        }
        return try await photoCapturer.capture(format: format, deviceZoom: Double(device.videoZoomFactor), dngURL: dngURL, heicURL: heicURL)
    }
}

extension CameraSession {
    /// One result per finished clip, after its sidecar is written.
    nonisolated var recordings: AsyncStream<RecordingResult> { recordingResults }

    /// Starts recording `option`, which the session must already be configured for, to `url`. Recording stops on its own
    /// when free space falls to `minFreeBytes`. ProRes RAW records with white balance locked, and the earlier mode returns
    /// when that clip finishes, however it ends; other codecs leave white balance alone.
    func startRecording(option: VideoOption, url: URL, minFreeBytes: Int64) throws(RecordingError) {
        guard session.isRunning else { throw .sessionNotRunning }
        guard let device = videoInput?.device, session.outputs.contains(recorder.output) else { throw .outputNotAttached }
        if option.codec.family == .raw {
            try lockWhiteBalance(on: device)
        }
        do throws(RecordingError) {
            try recorder.start(option: option, url: url, minFreeBytes: minFreeBytes, device: device) { [weak self] in
                guard let self else { return }
                Task { await self.restoreWhiteBalance() }
            }
        } catch {
            restoreWhiteBalance()
            throw error
        }
    }

    func stopRecording() {
        recorder.stop()
    }

    /// Levels 0...1 per microphone channel; empty without a microphone or outside video mode.
    func audioLevels() -> [Double] {
        guard session.outputs.contains(recorder.output) else { return [] }
        return recorder.audioLevels()
    }

    /// Locks white balance at the current gains (AVCaptureDevice.h, AVCaptureWhiteBalanceModeLocked) and remembers the
    /// mode it replaced. Nothing is remembered when it was already locked, so a lock the user chose is left in place.
    private func lockWhiteBalance(on device: AVCaptureDevice) throws(RecordingError) {
        let previous = device.whiteBalanceMode
        guard previous != .locked, device.isWhiteBalanceModeSupported(.locked) else { return }
        do {
            try device.lockForConfiguration()
        } catch {
            throw .whiteBalanceNotSet(reason: String(describing: error))
        }
        device.whiteBalanceMode = .locked
        device.unlockForConfiguration()
        whiteBalanceRestore = (device, previous)
    }

    /// Returns white balance to the mode a ProRes RAW clip replaced; a failure is logged and recording carries on.
    private func restoreWhiteBalance() {
        guard let restore = whiteBalanceRestore else { return }
        whiteBalanceRestore = nil
        let (device, mode) = restore
        guard device.isWhiteBalanceModeSupported(mode) else {
            Self.logger.error("[CameraSession:restoreWhiteBalance] Mode no longer supported — {mode: \(mode.rawValue)}")
            return
        }
        do {
            try device.lockForConfiguration()
        } catch {
            Self.logger.error("[CameraSession:restoreWhiteBalance] Cannot lock the camera for configuration — {mode: \(mode.rawValue), reason: \(String(describing: error), privacy: .public)}")
            return
        }
        device.whiteBalanceMode = mode
        device.unlockForConfiguration()
    }
}

extension CameraSession {
    /// What the current camera reports now; empty while the session is stopped or has no camera.
    /// Read on the session queue, so a lens switch is never seen half done.
    func currentReadouts() -> LiveReadouts {
        guard session.isRunning, let device = videoInput?.device else { return LiveReadouts() }
        let duration = device.exposureDuration
        // AVCaptureDevice.h: the conversion throws NSRangeException for gains outside 1.0...maxWhiteBalanceGain.
        let gains = device.deviceWhiteBalanceGains
        let maxGain = device.maxWhiteBalanceGain
        let isGainInRange = { (gain: Float) in gain >= 1 && gain <= maxGain }
        let whiteBalance = isGainInRange(gains.redGain) && isGainInRange(gains.greenGain) && isGainInRange(gains.blueGain)
            ? device.temperatureAndTintValues(for: gains) : nil
        return LiveReadouts(iso: device.iso,
                            shutterSeconds: duration.isNumeric ? duration.seconds : nil,
                            kelvin: whiteBalance?.temperature,
                            tint: whiteBalance?.tint,
                            exposureBias: device.exposureTargetBias,
                            lensPosition: device.lensPosition)
    }

    /// Replaces the session's controls with `kinds` for the current camera. A slider is left out when the active format
    /// recommends no range for it, because its initializer throws an Objective-C exception for a device that cannot
    /// set that property (AVCaptureSystemZoomSlider.h, AVCaptureSystemExposureBiasSlider.h), and when the session
    /// cannot add it (`maxControlsCount` is known only at run time). Removing and adding happen in one configuration change.
    private func installSystemControls(_ kinds: [SystemControlKind]) {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        for control in session.controls {
            session.removeControl(control)
        }
        guard !kinds.isEmpty, let device = videoInput?.device else { return }
        if session.controlsDelegate == nil {
            session.setControlsDelegate(controlsDelegate, queue: queue)
        }
        for kind in kinds {
            let control: AVCaptureControl
            switch kind {
            case .zoom:
                guard device.activeFormat.systemRecommendedVideoZoomRange != nil else {
                    Self.logger.error("[CameraSession:installSystemControls] No recommended zoom range — {device: \(device.localizedName, privacy: .public)}")
                    continue
                }
                control = AVCaptureSystemZoomSlider(device: device)
            case .exposureBias:
                guard device.activeFormat.systemRecommendedExposureBiasRange != nil else {
                    Self.logger.error("[CameraSession:installSystemControls] No recommended exposure bias range — {device: \(device.localizedName, privacy: .public)}")
                    continue
                }
                control = AVCaptureSystemExposureBiasSlider(device: device)
            }
            guard session.canAddControl(control) else {
                Self.logger.error("[CameraSession:installSystemControls] Cannot add control — {kind: \(String(describing: kind), privacy: .public), count: \(self.session.controls.count), max: \(self.session.maxControlsCount)}")
                continue
            }
            session.addControl(control)
        }
    }
}
