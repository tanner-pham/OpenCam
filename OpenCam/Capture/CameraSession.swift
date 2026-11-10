import AVFoundation

/// Owns `AVCaptureSession` and every device it touches, on its own serial queue.
actor CameraSession {
    nonisolated let previewSource: PreviewSource
    nonisolated let events: AsyncStream<SessionEvent>

    private let queue = DispatchSerialQueue(label: "opencam.session")
    private let session: AVCaptureSession
    private let continuation: AsyncStream<SessionEvent>.Continuation
    private let notificationTokens: [any NSObjectProtocol]
    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private var pressureObservation: NSKeyValueObservation?

    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    init() {
        let session = AVCaptureSession()
        // activeColorSpace is chosen per option; the session would otherwise override it.
        session.automaticallyConfiguresCaptureDeviceForWideColor = false
        let (events, continuation) = AsyncStream.makeStream(of: SessionEvent.self)
        self.session = session
        self.previewSource = PreviewSource(session: session)
        self.events = events
        self.continuation = continuation
        self.notificationTokens = Self.observeNotifications(of: session, continuation: continuation)
    }

    isolated deinit {
        for token in notificationTokens {
            NotificationCenter.default.removeObserver(token)
        }
        continuation.finish()
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

    func configure(_ configuration: SessionConfiguration) throws(CameraSessionError) {
        let lens = configuration.lens
        guard let device = AVCaptureDevice(uniqueID: lens.deviceUniqueID) else {
            throw .deviceMissing(lensID: lens.id)
        }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        try attachVideo(device, lensID: lens.id)
        try attachAudio(configuration.includesAudio)
        try applyFormat(configuration, to: device)
        pressureObservation = Self.observePressure(of: device, continuation: continuation)
    }

    func start() {
        guard !session.isRunning else { return }
        session.startRunning()
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

    private func attachAudio(_ includesAudio: Bool) throws(CameraSessionError) {
        guard includesAudio else {
            if let audioInput { session.removeInput(audioInput) }
            audioInput = nil
            return
        }
        guard audioInput == nil else { return }
        guard let microphone = AVCaptureDevice.default(for: .audio) else {
            throw .deviceMissing(lensID: "microphone")
        }
        guard let input = try? AVCaptureDeviceInput(device: microphone), session.canAddInput(input) else {
            throw .cannotAddInput(lensID: "microphone")
        }
        session.addInput(input)
        audioInput = input
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
        of session: AVCaptureSession, continuation: AsyncStream<SessionEvent>.Continuation
    ) -> [any NSObjectProtocol] {
        let center = NotificationCenter.default
        let interrupted = center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: nil) { notification in
            let rawReason = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int ?? 0
            continuation.yield(.interrupted(InterruptionReason(avReason: rawReason)))
        }
        let ended = center.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: nil) { _ in
            continuation.yield(.interruptionEnded)
        }
        let runtimeError = center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil) { notification in
            let error = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError
            let detail = error.map { "domain: \($0.domain), code: \($0.code), \($0.localizedDescription)" } ?? "no error"
            continuation.yield(.runtimeError("[CameraSession:runtimeError] Session stopped — {\(detail)}"))
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
