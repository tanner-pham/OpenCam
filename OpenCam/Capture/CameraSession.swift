import AVFoundation
import OSLog
import Synchronization

/// Owns `AVCaptureSession` and every device it touches, on its own serial queue.
actor CameraSession: SessionConfigurator {
    nonisolated let previewSource: PreviewSource
    nonisolated let events: AsyncStream<SessionEvent>
    /// Backs `recordings`: one result per finished clip, yielded by the recorder.
    nonisolated let recordingResults: AsyncStream<RecordingResult>

    private let queue = DispatchSerialQueue(label: "opencam.session")
    let session: AVCaptureSession
    private let continuation: AsyncStream<SessionEvent>.Continuation
    private let recordingContinuation: AsyncStream<RecordingResult>.Continuation
    /// Its output is attached in video mode on the system recorder path only.
    let recorder: MovieRecorder
    /// The writer path's outputs, queues and sink. Made the first time the writer path is used, so a session that only records
    /// with the movie output never builds them and its outputs are exactly as they always were; see `writerRecorder`.
    private(set) var writerRecorderStorage: WriterRecorder?
    /// Reads free space once a second while a writer clip records, and ends the clip when it falls to the minimum.
    private var storageWatch: Task<Void, Never>?
    /// Ends the wait for a writer clip's file when the writer never reports it finished; see `armFinishTimeout`.
    private var finishTimeout: Task<Void, Never>?
    /// Registered on the first `start()`, because the runtime-error observer needs a reference to this actor.
    private var notificationTokens: [any NSObjectProtocol] = []
    var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    /// Its output is attached in photo mode only.
    private let photoCapturer = PhotoCapturer()
    /// Draws the selected look on the viewfinder; fed by `frameOutput`, which is attached only while a configuration needs frames.
    private let frames: FramePipeline
    /// Preview-sized buffers for the look on the viewfinder (AVCaptureVideoDataOutput.h, `deliversPreviewSizedOutputBuffers`).
    /// Attached only while the applied configuration's `needsFrames` is true, so with no look the outputs are as before.
    private let frameOutput: AVCaptureVideoDataOutput
    private var pressureObservation: NSKeyValueObservation?
    /// The session's own part of the launch, written as one journal line when the first `start()` returns, then nil.
    /// Its clock is the process start, like the model's line.
    private var launchMarks: LaunchTimeline? = LaunchTimeline()
    /// True while a media-services-reset restart runs, so a reset during that restart is not retried; cleared when it
    /// ends, whether it worked or not.
    private var isRestartingAfterReset = false
    /// Set by `start()` and cleared by `stop()`; a media-services reset restarts the session only while it is set,
    /// so a session stopped on purpose (during a rescan, say) stays stopped.
    private var isMeantToRun = false
    /// Restored when a later configure fails.
    var lastWorkingConfiguration: SessionConfiguration? {
        didSet { appliedConfiguration.withLock { $0 = lastWorkingConfiguration.map { "lens: \($0.lens.id), mode: \($0.mode.rawValue)" } } }
    }
    /// The lens and mode of `lastWorkingConfiguration`, for the runtime error's message, which is written off the session queue.
    private nonisolated let appliedConfiguration = Mutex<String?>(nil)
    /// The white-balance mode a ProRes RAW recording replaced, restored when that recording finishes.
    var whiteBalanceRestore: (device: AVCaptureDevice, mode: AVCaptureDevice.WhiteBalanceMode)?
    /// What the last `applyManual` left on the current camera; nil after every configure, which returns the camera to
    /// automatic, so the next apply sets every group.
    var appliedManual: ManualSettings?
    /// True from the start of a ProRes RAW clip, which records with white balance locked, until `restoreWhiteBalance` runs.
    var isRAWClipRecording = false
    /// Held here because the session does not keep its controls delegate alive.
    private let controlsDelegate: CameraControlsDelegate
    static let logger = Logger(subsystem: "local.opencam.app", category: "CameraSession")

    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    init() {
        let session = AVCaptureSession()
        // activeColorSpace is chosen per option; the session would otherwise override it. Photo mode on the photo preset
        // turns it on for its own configuration (`configureSession`).
        session.automaticallyConfiguresCaptureDeviceForWideColor = false
        let (events, continuation) = AsyncStream.makeStream(of: SessionEvent.self)
        let (recordingResults, recordingContinuation) = AsyncStream.makeStream(of: RecordingResult.self)
        let frames = FramePipeline()
        let frameOutput = AVCaptureVideoDataOutput()
        frameOutput.alwaysDiscardsLateVideoFrames = true
        // Must be turned off before deliversPreviewSizedOutputBuffers can be set (AVCaptureVideoDataOutput.h).
        frameOutput.automaticallyConfiguresOutputBufferDimensions = false
        frameOutput.deliversPreviewSizedOutputBuffers = true
        frameOutput.setSampleBufferDelegate(frames, queue: frames.queue)
        self.session = session
        self.frames = frames
        self.frameOutput = frameOutput
        self.previewSource = PreviewSource(session: session, frames: frames)
        self.events = events
        self.continuation = continuation
        self.controlsDelegate = CameraControlsDelegate(events: continuation)
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
        var access = currentAccess()
        if access.camera == .notDetermined {
            access.camera = await AVCaptureDevice.requestAccess(for: .video) ? .authorized : .denied
        }
        if access.camera == .authorized, access.microphone == .notDetermined {
            access.microphone = await AVCaptureDevice.requestAccess(for: .audio) ? .authorized : .denied
        }
        return access
    }

    /// On failure the last configuration that worked is applied again, so the session keeps running as it was,
    /// and the original error is thrown. If that restore fails too, a runtime error is reported.
    /// Refused while recording, because changing the format or outputs ends the clip.
    /// The Camera Control's system controls are installed last, for the device and mode now applied.
    func configure(_ configuration: SessionConfiguration) throws(CameraSessionError) {
        guard !recorder.output.isRecording, writerRecorderStorage?.isClipInFlight != true else { throw .recordingInProgress }
        // A configure that fails with no restore leaves the camera in a state nothing tracks, so nothing is assumed to hold.
        appliedManual = nil
        let timing = (start: ContinuousClock.now, previous: lastWorkingConfiguration)
        launchMarks?.mark("session configure")
        defer {
            launchMarks?.mark("session configured")
            TimingJournal.configure(configuration, after: timing.previous, since: timing.start)
        }
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
        let isOnPhotoPreset = try configureSession(configuration, device: device)
        if isOnPhotoPreset {
            // After the commit, so the preset's format is the active one.
            try applyPresetPhoto(configuration, to: device)
        }
        pressureObservation = Self.observePressure(of: device, continuation: continuation)
        // Every configure returns the camera to automatic, in step with the model, which does the same when it queues one.
        resetManual()
    }

    /// One configuration change, committed on return also when it throws. Returns whether photo mode is on the photo
    /// preset, whose format, zoom and photo size are applied only after this commit (`applyPresetPhoto`).
    private func configureSession(_ configuration: SessionConfiguration, device: AVCaptureDevice) throws(CameraSessionError) -> Bool {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        // Input priority: the device's activeFormat dictates quality, and the session never changes it
        // (AVCaptureSessionPreset.h, AVCaptureSessionPresetInputPriority).
        if session.canSetSessionPreset(.inputPriority) {
            session.sessionPreset = .inputPriority
        }
        try attachVideo(device, lensID: configuration.lens.id)
        attachAudio(configuration.includesAudio)
        try attachPhotoOutput(configuration.mode == .photo)
        let isVideo = configuration.mode == .video
        try attachMovieOutput(isVideo && configuration.recorder == .system)
        try attachWriterOutputs(isVideo && configuration.recorder == .writer)
        attachFrameOutput(configuration.needsFrames)
        // Photo mode takes the photo preset when the session allows it: only there does the Duo offer Bayer RAW (measured
        // 2026-11-10). The preset picks the format, so neither the format nor the colour space is set by hand, and the
        // session chooses wide colour itself (AVCaptureSession.h, automaticallyConfiguresCaptureDeviceForWideColor).
        // Otherwise, and always in video mode, the flag stays off as set in init and the format is chosen below.
        let isOnPhotoPreset = configuration.mode == .photo && session.canSetSessionPreset(.photo)
        session.automaticallyConfiguresCaptureDeviceForWideColor = isOnPhotoPreset
        if isOnPhotoPreset {
            session.sessionPreset = .photo
            return true
        }
        try applyFormat(configuration, to: device)
        if isVideo, configuration.recorder == .writer, let option = configuration.video {
            // After the camera's format is set, which decides the pixel formats the output offers.
            guard writerRecorder.preparePixelFormat(for: option.colour) else { throw .cannotAddOutput(name: "record frames") }
        }
        if configuration.mode == .photo {
            try applyPhotoDimensions(configuration.photo, format: device.activeFormat)
        }
        return false
    }

    /// Photo mode on the photo preset, after the configuration that selected it was committed: the lens's zoom and the
    /// selected photo size, both checked against the active format the preset chose. No format, colour space or frame
    /// duration is set: setting activeFormat would return the session to input priority (AVCaptureDevice.h), and a preset
    /// change already resets the frame durations to the format's defaults (AVCaptureDevice.h, activeVideoMinFrameDuration).
    private func applyPresetPhoto(_ configuration: SessionConfiguration, to device: AVCaptureDevice) throws(CameraSessionError) {
        do {
            try device.lockForConfiguration()
        } catch {
            throw .lockFailed(reason: String(describing: error))
        }
        defer { device.unlockForConfiguration() }
        let zoom = CGFloat(configuration.lens.zoomFactor)
        // A zoom above videoMaxZoomFactor raises NSRangeException (AVCaptureDevice.h, videoZoomFactor).
        guard zoom <= device.activeFormat.videoMaxZoomFactor else {
            throw .noMatchingFormat(option: "zoom \(configuration.lens.label)")
        }
        device.videoZoomFactor = zoom
        try applyPhotoDimensions(configuration.photo, format: device.activeFormat)
    }

    func start() {
        isMeantToRun = true
        if notificationTokens.isEmpty {
            notificationTokens = Self.observeNotifications(of: session, owner: self, continuation: continuation)
        }
        guard !session.isRunning else { return }
        launchMarks?.mark("session startRunning")
        session.startRunning()
        launchMarks?.mark("session running")
        allowHapticsWhileRecording()
        writeLaunchLine()
    }

    /// The session's launch line, once, after the first start: the marks, then what was applied and whether a preview layer
    /// was already connected (`preview yes` means the layer joined before the session started).
    private func writeLaunchLine() {
        guard var marks = launchMarks else { return }
        marks.mark("session started")
        if let applied = lastWorkingConfiguration { marks.note("\(applied.mode.rawValue) \(applied.lens.label)") }
        marks.note("audio \(audioInput != nil ? "yes" : "no")")
        marks.note("preview \(session.connections.contains { $0.videoPreviewLayer != nil } ? "yes" : "no")")
        launchMarks = nil
        ErrorJournal.record(marks.line)
    }

    /// After `AVError.Code.mediaServicesWereReset` the session is restarted once, if it is meant to run; `.restarted`
    /// follows when it runs again. A restart that fails leaves the session failed, and a later reset tries again.
    private func restartAfterMediaServicesReset() {
        guard isMeantToRun, !isRestartingAfterReset else { return }
        isRestartingAfterReset = true
        defer { isRestartingAfterReset = false }
        session.startRunning()
        guard session.isRunning else {
            Self.logger.error("[CameraSession:restartAfterMediaServicesReset] The session did not start again — {isRunning: false}")
            // A plain runtime error, not a reset, so the model leaves the reset and offers Try again.
            continuation.yield(.runtimeError(RuntimeErrorText.restartFailedMessage(applied: appliedConfiguration.withLock { $0 })))
            return
        }
        // The device may have come back with settings of its own, so manual values are not assumed to hold.
        resetManual()
        continuation.yield(.restarted)
    }

    func stop() {
        isMeantToRun = false
        // A clip being written ends at its last frame; with the camera stopped no frame would ever end it otherwise.
        endWriterClip(.cameraStopped)
        guard session.isRunning else { return }
        session.stopRunning()
    }

    /// Stops the session and removes its camera input, and the controls bound to that camera, so the capability scanner
    /// can add the camera to a session of its own. The next `configure` attaches a camera again; the last working
    /// configuration is forgotten, so a configure that fails then restores nothing and the caller knows none is attached.
    func releaseCameras() {
        stop()
        lastWorkingConfiguration = nil
        appliedManual = nil
        installSystemControls([])
        guard let videoInput else { return }
        session.beginConfiguration()
        session.removeInput(videoInput)
        session.commitConfiguration()
        self.videoInput = nil
    }

    /// Releases a saved start's camera and marks, in one actor turn so no event lands between them, where its events end.
    func releaseSavedStart() {
        releaseCameras()
        continuation.yield(.savedStartReleased)
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

    /// While the microphone is live, iOS plays no haptics or system sounds unless the app's audio session allows them
    /// (AVAudioSession.h: `setAllowHapticsAndSystemSoundsDuringRecording`, default NO), so the record start and stop haptics
    /// would be silent in video mode. This app never sets up its audio session itself: the capture session does it
    /// (`automaticallyConfiguresApplicationAudioSession`, default YES) once it runs with a microphone. So the setting is applied
    /// after that, when the session starts and again just before each recording, and only when it is not already on.
    /// A failure is logged and the recording goes on without haptics.
    private func allowHapticsWhileRecording() {
        guard audioInput != nil else { return }
        let audio = AVAudioSession.sharedInstance()
        guard !audio.allowHapticsAndSystemSoundsDuringRecording else { return }
        do {
            try audio.setAllowHapticsAndSystemSoundsDuringRecording(true)
        } catch {
            Self.logger.error("[CameraSession:allowHapticsWhileRecording] Haptics stay muted while recording — {category: \(audio.category.rawValue, privacy: .public), reason: \(error.localizedDescription, privacy: .public)}")
        }
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

    /// The writer path's outputs: full-size video frames and, with the microphone attached, its sound. Both are detached on any
    /// other path. The video connection is made neutral here, inside the configuration change, like the look's frame output, so
    /// buffers arrive in the sensor's own orientation, unmirrored, and the clip's track carries the rotation.
    private func attachWriterOutputs(_ isAttached: Bool) throws(CameraSessionError) {
        guard isAttached else {
            guard let writerRecorderStorage else { return }
            for output in [writerRecorderStorage.videoOutput, writerRecorderStorage.audioOutput] where session.outputs.contains(output) {
                session.removeOutput(output)
            }
            return
        }
        let writer = writerRecorder
        let video = writer.videoOutput
        if !session.outputs.contains(video) {
            guard session.canAddOutput(video) else { throw .cannotAddOutput(name: "record frames") }
            session.addOutput(video)
        }
        if let connection = video.connection(with: .video) {
            if connection.videoRotationAngle != 0, connection.isVideoRotationAngleSupported(0) {
                connection.videoRotationAngle = 0
            }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = false
            }
        }
        let sound = writer.audioOutput
        if audioInput != nil {
            if !session.outputs.contains(sound) {
                if session.canAddOutput(sound) {
                    session.addOutput(sound)
                } else {
                    continuation.yield(.microphoneUnavailable("[CameraSession:configure] Cannot add output — {output: record sound}"))
                }
            }
        } else if session.outputs.contains(sound) {
            session.removeOutput(sound)
        }
    }

    /// Attached only while a look needs frames; detached otherwise, so a configuration without a look has the outputs it
    /// always had. An output that cannot be added never fails the configure: `.framesUnavailable` says so and the
    /// viewfinder keeps the preview layer. Its connection is made neutral here, while the session is being configured, so
    /// buffers always arrive in the sensor's own orientation, unmirrored, and the pipeline does all turning and mirroring.
    private func attachFrameOutput(_ isAttached: Bool) {
        let isPresent = session.outputs.contains(frameOutput)
        guard isAttached else {
            if isPresent { session.removeOutput(frameOutput) }
            return
        }
        if !isPresent {
            guard session.canAddOutput(frameOutput) else {
                Self.logger.error("[CameraSession:attachFrameOutput] Cannot add output — {name: frames}")
                continuation.yield(.framesUnavailable)
                return
            }
            session.addOutput(frameOutput)
        }
        if let connection = frameOutput.connection(with: .video) {
            // The one place the angle is set: once per configuration, inside beginConfiguration/commitConfiguration, never
            // on a running session. AVCaptureSession.h:1085 warns that a data output's rotation physically rotates buffers
            // and needs a lengthy pipeline reconfiguration, so it belongs before running; :1087 says some devices default
            // the front camera's video data to 180 degrees and advises setting 0; :1089 says ProRes RAW buffers must be at 0.
            // Set only when it differs, so a connection already at 0 costs no reconfiguration.
            if connection.videoRotationAngle != 0, connection.isVideoRotationAngleSupported(0) {
                connection.videoRotationAngle = 0
            }
            // isVideoMirrored cannot be set while the connection adjusts it itself (AVCaptureSession.h:1050).
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = false
            }
        }
        frames.setCamera(isFront: videoInput?.device.position == .front)
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
        guard let space = AVCaptureColorSpace(rawValue: option.colour.captureColorSpaceRawValue) else {
            throw .noMatchingFormat(option: "colour \(option.colour.rawValue)")
        }
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
        let interrupted = center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: nil) { [weak owner] notification in
            let rawReason = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int ?? 0
            continuation.yield(.interrupted(InterruptionReason(avReason: rawReason)))
            // Backgrounding is an interruption too. A writer clip ends at its last frame; the writer fails in the background.
            Task { await owner?.endWriterClip(.interrupted) }
        }
        let ended = center.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: nil) { _ in
            continuation.yield(.interruptionEnded)
        }
        let runtimeError = center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil) { [weak owner] notification in
            let error = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError
            continuation.yield(.runtimeError(RuntimeErrorText.message(for: error, applied: owner?.appliedConfiguration.withLock { $0 })))
            Task { await owner?.endWriterClip(.cameraStopped) }
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
        do throws(PhotoCaptureError) {
            let result = try await requestPhoto(format: format, dngURL: dngURL, heicURL: heicURL)
            if let error = result.error {
                ErrorJournal.record("[CameraSession:capturePhoto] \(error.description) — {\(photoContext(format))}")
            }
            return result
        } catch {
            ErrorJournal.record("[CameraSession:capturePhoto] \(error.description) — {\(photoContext(format))}")
            throw error
        }
    }

    /// What the session offered when a photo request was refused or failed, for the error journal.
    private func photoContext(_ format: PhotoFormat) -> String {
        let output = photoCapturer.output
        let device = videoInput?.device
        let active = device.map { device -> String in
            let size = device.activeFormat.formatDescription.dimensions
            return "\(size.width)x\(size.height) subtype \(device.activeFormat.formatDescription.mediaSubType.rawValue)"
        } ?? "none"
        let maximum = output.maxPhotoDimensions
        return "asked: \(format.rawValue), preset: \(session.sessionPreset.rawValue), running: \(session.isRunning), "
            + "activeFormat: \(active), zoom: \(device.map { Double($0.videoZoomFactor) } ?? 0), "
            + "maxPhoto: \(maximum.width)x\(maximum.height), rawFormats: \(output.availableRawPhotoPixelFormatTypes), "
            + "rawFileTypes: \(output.availableRawPhotoFileTypes.map(\.rawValue)), outputs: \(session.outputs.count), "
            + "controls: \(session.controls.count)"
    }

    private func requestPhoto(format: PhotoFormat, dngURL: URL, heicURL: URL) async throws(PhotoCaptureError) -> PhotoCaptureResult {
        guard let device = videoInput?.device, session.outputs.contains(photoCapturer.output) else {
            throw .captureFailed(reason: "photo output not attached")
        }
        // Each request asks for the output's maximum, which must be a size the active format lists.
        let maximum = photoCapturer.output.maxPhotoDimensions
        guard device.activeFormat.supportedMaxPhotoDimensions.contains(where: { $0.width == maximum.width && $0.height == maximum.height }) else {
            throw .captureFailed(reason: "photo size \(maximum.width) x \(maximum.height) not offered by the active format")
        }
        // A manual exposure is kept in the photo only with the speed prioritization (AVCaptureDevice.h, `exposureMode`).
        return try await photoCapturer.capture(format: format, deviceZoom: Double(device.videoZoomFactor),
                                               isExposureManual: device.exposureMode == .custom, dngURL: dngURL, heicURL: heicURL)
    }
}

extension CameraSession {
    /// One result per finished clip, after its sidecar is written.
    nonisolated var recordings: AsyncStream<RecordingResult> { recordingResults }

    /// Starts recording `option`, which the session must already be configured for, to `url`. Recording stops on its own
    /// when free space falls to `minFreeBytes`. ProRes RAW records with white balance locked, and the earlier mode returns
    /// when that clip finishes, however it ends; other codecs leave white balance alone.
    /// `dropPolicy` is read by the writer path only. The applied configuration's recorder picks the path.
    func startRecording(option: VideoOption, url: URL, minFreeBytes: Int64, dropPolicy: DropPolicy) throws(RecordingError) {
        if lastWorkingConfiguration?.recorder == .writer {
            try startWriterRecording(option: option, url: url, minFreeBytes: minFreeBytes, dropPolicy: dropPolicy)
            return
        }
        guard session.isRunning else { throw .sessionNotRunning }
        guard let device = videoInput?.device, session.outputs.contains(recorder.output) else { throw .outputNotAttached }
        if option.codec.family == .raw {
            try lockWhiteBalance(on: device)
            // Until `restoreWhiteBalance`, an automatic white balance asked for by hand waits for the clip to end.
            isRAWClipRecording = true
        }
        allowHapticsWhileRecording()
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

    /// Returns whether a clip was in flight; false means no recording result will follow.
    func stopRecording() -> Bool {
        if let writer = writerRecorderStorage, writer.isClipInFlight || writer.hasResultPending {
            return endWriterClip(.user)
        }
        return recorder.stop()
    }

    /// Levels 0...1 per microphone channel; empty without a microphone or outside video mode.
    func audioLevels() -> [Double] {
        if let writer = writerRecorderStorage, session.outputs.contains(writer.audioOutput) { return writer.audioLevels() }
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
    /// The clip is over for manual white balance either way, so the flag is cleared even when there is nothing to restore.
    private func restoreWhiteBalance() {
        isRAWClipRecording = false
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

extension CameraSession {
    /// How long a writer clip's file may take to finish after the clip ends, before the app reports it as it is.
    private static let finishTimeoutSeconds = 10

    /// The writer path, made on first use. Its finish handler comes back to this actor to collect the clip.
    private var writerRecorder: WriterRecorder {
        if let writerRecorderStorage { return writerRecorderStorage }
        let made = WriterRecorder(results: recordingContinuation, events: continuation) { [weak self] in
            guard let self else { return }
            Task { await self.writerClipFinished() }
        }
        writerRecorderStorage = made
        return made
    }

    /// Opens the writer for `option`, which the session must already be configured for on the writer path, and starts a once-a-second
    /// watch on free space. Nothing is left running when this throws.
    private func startWriterRecording(option: VideoOption, url: URL, minFreeBytes: Int64, dropPolicy: DropPolicy) throws(RecordingError) {
        guard session.isRunning else { throw .sessionNotRunning }
        let writer = writerRecorder
        guard let device = videoInput?.device, session.outputs.contains(writer.videoOutput) else { throw .writerNotAttached }
        guard !writer.isClipInFlight else { throw .alreadyRecording }
        allowHapticsWhileRecording()
        let recordsSound = session.outputs.contains(writer.audioOutput) && writer.audioOutput.connection(with: .audio)?.isActive == true
        try writer.start(option: option, url: url, minFreeBytes: minFreeBytes, policy: dropPolicy, device: device, recordsSound: recordsSound)
        watchStorage()
    }

    /// Ends the writer clip for `end`. Returns whether a result will follow. A clip that does not report its file finished within
    /// ten seconds is collected as it is.
    @discardableResult
    func endWriterClip(_ end: WriterEnd) -> Bool {
        guard let writer = writerRecorderStorage else { return false }
        let willFollow = writer.end(end)
        if writer.isClipInFlight { armFinishTimeout() }
        return willFollow
    }

    /// The writer reported the clip's file finished.
    private func writerClipFinished() {
        collectWriterClip(timedOut: false)
    }

    private func collectWriterClip(timedOut: Bool) {
        guard let writer = writerRecorderStorage else { return }
        writer.collect(timedOut: timedOut)
        guard !writer.isClipInFlight else { return }
        storageWatch?.cancel()
        storageWatch = nil
        finishTimeout?.cancel()
        finishTimeout = nil
    }

    private func armFinishTimeout() {
        guard finishTimeout == nil else { return }
        finishTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.finishTimeoutSeconds))
            guard !Task.isCancelled, let self else { return }
            await self.finishTimedOut()
        }
    }

    private func finishTimedOut() {
        guard !Task.isCancelled else { return }
        if let writer = writerRecorderStorage, writer.isClipInFlight {
            let message = "[CameraSession:finishTimedOut] The writer did not finish the clip in time — {seconds: \(Self.finishTimeoutSeconds)}"
            Self.logger.error("\(message, privacy: .public)")
            ErrorJournal.record(message)
        }
        collectWriterClip(timedOut: true)
    }

    /// Reads free space once a second and passes it to the clip, which ends at its last frame when it falls to the minimum.
    private func watchStorage() {
        storageWatch?.cancel()
        storageWatch = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                await self.checkStorage()
            }
        }
    }

    private func checkStorage() {
        writerRecorderStorage?.storage(freeBytes: FreeSpace.readBytes())
    }
}
