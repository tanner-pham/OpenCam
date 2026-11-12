import AVFoundation

/// A step of the lens check that cannot go on; the message names the step and says why.
nonisolated struct LensCheckFailure: Error, Sendable {
    let message: String
}

/// A video size, rate and colour the check runs on.
nonisolated struct LensCheckFormat: Sendable {
    let label: String
    let width: Int32
    let height: Int32
    let framesPerSecond: Int
    let isHLG: Bool

    static let uhd30HLG = LensCheckFormat(label: "4K 30 HLG", width: 3840, height: 2160, framesPerSecond: 30, isHLG: true)
    static let uhd60HLG = LensCheckFormat(label: "4K 60 HLG", width: 3840, height: 2160, framesPerSecond: 60, isHLG: true)
    static let hd30SDR = LensCheckFormat(label: "1080p 30 Rec. 709", width: 1920, height: 1080, framesPerSecond: 30, isHLG: false)
}

/// One session of the lens check, built the way `CameraSession` builds its own: input priority, the camera's format set by
/// hand, and either the writer path's full-size data output, the movie output with a preview-sized data output, or the photo
/// output on the photo preset. Used from one task at a time.
nonisolated final class LensCheckRig {
    enum Outputs { case frames, movie, photo }

    let session = AVCaptureSession()
    let tap = LensCheckTap()
    let dataOutput = AVCaptureVideoDataOutput()
    let movieOutput = AVCaptureMovieFileOutput()
    let photoOutput = AVCapturePhotoOutput()
    private(set) var device: AVCaptureDevice
    private var input: AVCaptureDeviceInput
    private let outputs: Outputs
    private let format: LensCheckFormat?
    private var observations: [NSKeyValueObservation] = []
    private(set) var setup: [String: String] = [:]

    init(device: AVCaptureDevice, outputs: Outputs, format: LensCheckFormat?) throws(LensCheckFailure) {
        self.device = device
        self.outputs = outputs
        self.format = format
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            throw LensCheckFailure(message: "The camera input could not be made: \(error.localizedDescription)")
        }
        session.beginConfiguration()
        var isCommitted = false
        defer { if !isCommitted { session.commitConfiguration() } }
        if session.canSetSessionPreset(.inputPriority) { session.sessionPreset = .inputPriority }
        session.automaticallyConfiguresCaptureDeviceForWideColor = false
        guard session.canAddInput(input) else { throw LensCheckFailure(message: "The session cannot take \(device.localizedName)") }
        session.addInput(input)
        switch outputs {
        case .frames:
            // As `WriterRecorder` sets its output up: full-size frames, none thrown away.
            dataOutput.alwaysDiscardsLateVideoFrames = false
            dataOutput.automaticallyConfiguresOutputBufferDimensions = false
            dataOutput.deliversPreviewSizedOutputBuffers = false
            try add(dataOutput, name: "frames")
            neutralise()
        case .movie:
            try add(movieOutput, name: "movie")
            // As `CameraSession` sets its look output up: preview-sized, late frames thrown away.
            dataOutput.alwaysDiscardsLateVideoFrames = true
            dataOutput.automaticallyConfiguresOutputBufferDimensions = false
            dataOutput.deliversPreviewSizedOutputBuffers = true
            try add(dataOutput, name: "frames")
            neutralise()
        case .photo:
            try add(photoOutput, name: "photo")
            guard session.canSetSessionPreset(.photo) else { throw LensCheckFailure(message: "The session cannot use the photo preset") }
            session.automaticallyConfiguresCaptureDeviceForWideColor = true
            session.sessionPreset = .photo
        }
        if let format, outputs != .photo { try apply(format, to: device) }
        session.commitConfiguration()
        isCommitted = true
        if outputs == .frames { preparePixelFormat() }
        if outputs != .photo { dataOutput.setSampleBufferDelegate(tap, queue: tap.queue) }
        observe(device)
        setup["camera"] = device.localizedName
        setup["active format"] = Self.describe(device.activeFormat)
        setup["colour space"] = Self.name(device.activeColorSpace)
        if outputs != .photo {
            setup["data output pixel formats offered"] = dataOutput.availableVideoPixelFormatTypes.map { LensCheckTap.fourCC($0) }.joined(separator: " ")
            setup["data output codecs for a writer (mov)"] = dataOutput.availableVideoCodecTypesForAssetWriter(writingTo: .mov).map(\.rawValue).joined(separator: " ")
        }
    }

    /// Starts the session and, with a data output, waits up to three seconds for its first frame.
    func start() async throws(LensCheckFailure) {
        session.startRunning()
        guard session.isRunning else { throw LensCheckFailure(message: "The session did not start") }
        guard outputs != .photo else {
            try? await Task.sleep(for: .seconds(1))
            return
        }
        for _ in 0..<60 where tap.total == 0 {
            try? await Task.sleep(for: .milliseconds(50))
        }
        guard tap.total > 0 else { throw LensCheckFailure(message: "No frame arrived within 3 seconds") }
        setup.merge(tap.firstFrame) { _, new in new }
        setup["synchronisation clock is the host clock"] = String(session.synchronizationClock.map { CFEqual($0, CMClockGetHostTimeClock()) } ?? false)
    }

    func stop() {
        session.stopRunning()
        dataOutput.setSampleBufferDelegate(nil, queue: nil)
        observations.removeAll()
    }

    // MARK: Lens and zoom

    var isVirtual: Bool { device.isVirtualDevice }
    var canLockToLens: Bool { device.isPrimaryConstituentDeviceSwitchingBehaviorLockedWithDeviceSupported }
    /// The active lens of the combined camera, or the camera itself when it has only one.
    var lensName: String { isVirtual ? Self.name(device.activePrimaryConstituent) : Self.name(device) }

    /// Sets the zoom now. A zoom outside the range the camera allows at this moment is refused, because setting it raises an
    /// exception Swift cannot catch (AVCaptureDevice.h, `videoZoomFactor`).
    /// When the range does not hold `zoom` yet (a lens lock was just set or released), this waits for it, up to half a second,
    /// and returns how long it waited in milliseconds.
    @discardableResult
    func jump(to zoom: CGFloat) throws(LensCheckFailure) -> Double? {
        let waited = try waitForZoomRange(toHold: zoom)
        try lock()
        defer { device.unlockForConfiguration() }
        guard zoom >= device.minAvailableVideoZoomFactor, zoom <= device.maxAvailableVideoZoomFactor else {
            throw LensCheckFailure(message: "Zoom \(zoom) is outside \(device.minAvailableVideoZoomFactor)...\(device.maxAvailableVideoZoomFactor)")
        }
        device.videoZoomFactor = zoom
        return waited
    }

    private func waitForZoomRange(toHold zoom: CGFloat) throws(LensCheckFailure) -> Double? {
        let start = LensCheckTap.hostNow()
        var didWait = false
        while zoom < device.minAvailableVideoZoomFactor || zoom > device.maxAvailableVideoZoomFactor {
            guard LensCheckTap.hostNow() - start < 0.5 else {
                throw LensCheckFailure(message: "Zoom \(zoom) stayed outside \(device.minAvailableVideoZoomFactor)...\(device.maxAvailableVideoZoomFactor) for half a second")
            }
            didWait = true
            Thread.sleep(forTimeInterval: 0.002)
        }
        return didWait ? (LensCheckTap.hostNow() - start) * 1000 : nil
    }

    /// `rate` is in doublings a second (AVCaptureDevice.h, `rampToVideoZoomFactor:withRate:`).
    func ramp(to zoom: CGFloat, rate: Float) throws(LensCheckFailure) {
        try lock()
        defer { device.unlockForConfiguration() }
        guard zoom >= device.minAvailableVideoZoomFactor, zoom <= device.maxAvailableVideoZoomFactor else {
            throw LensCheckFailure(message: "Zoom \(zoom) is outside \(device.minAvailableVideoZoomFactor)...\(device.maxAvailableVideoZoomFactor)")
        }
        device.ramp(toVideoZoomFactor: zoom, withRate: rate)
    }

    /// Auto, or restricted with no fallback condition. Auto also releases a lens lock.
    func setBehaviour(_ behaviour: AVCaptureDevice.PrimaryConstituentDeviceSwitchingBehavior) throws(LensCheckFailure) {
        guard device.primaryConstituentDeviceSwitchingBehavior != .unsupported else {
            throw LensCheckFailure(message: "\(device.localizedName) does not switch lenses")
        }
        try lock()
        defer { device.unlockForConfiguration() }
        device.setPrimaryConstituentDeviceSwitchingBehavior(behaviour, restrictedSwitchingBehaviorConditions: [])
    }

    /// Locks the combined camera to one of its lenses, then sets the zoom. The lock clamps the zoom into that lens's range by
    /// itself. When the camera's zoom range has not yet moved to include `zoom`, this waits for it, up to half a second, and
    /// returns how long it waited in milliseconds.
    func lock(to lens: AVCaptureDevice, zoom: CGFloat) throws(LensCheckFailure) -> Double? {
        guard canLockToLens else { throw LensCheckFailure(message: "Locking to a lens is not supported") }
        // Already locked to this lens: the change is a zoom only, as a tap between 1x and 2x would be.
        if device.primaryConstituentDeviceSwitchingBehavior == .locked, device.activePrimaryConstituent?.uniqueID == lens.uniqueID {
            return try jump(to: zoom)
        }
        try lock()
        device.setPrimaryConstituentDeviceSwitchingBehaviorLockedWith(lens)
        if zoom >= device.minAvailableVideoZoomFactor, zoom <= device.maxAvailableVideoZoomFactor {
            device.videoZoomFactor = zoom
            device.unlockForConfiguration()
            return nil
        }
        device.unlockForConfiguration()
        return try jump(to: zoom)
    }

    /// The lenses the combined camera may fall back to when the longer one cannot focus or expose; nil puts back every lens it supports.
    func setFallbackLenses(_ lenses: [AVCaptureDevice]?) throws(LensCheckFailure) {
        try lock()
        defer { device.unlockForConfiguration() }
        device.fallbackPrimaryConstituentDevices = lenses ?? device.supportedFallbackPrimaryConstituentDevices
    }

    /// Today's lens change: the camera input is removed and another added, with the same format, in one configuration change,
    /// and the writer path's pixel format is set again after it, as `CameraSession.configure` does.
    func swapInput(to other: AVCaptureDevice) throws(LensCheckFailure) {
        let replacement: AVCaptureDeviceInput
        do {
            replacement = try AVCaptureDeviceInput(device: other)
        } catch {
            throw LensCheckFailure(message: "The camera input could not be made: \(error.localizedDescription)")
        }
        session.beginConfiguration()
        session.removeInput(input)
        guard session.canAddInput(replacement) else {
            if session.canAddInput(input) { session.addInput(input) }
            session.commitConfiguration()
            throw LensCheckFailure(message: "The session cannot take \(other.localizedName)")
        }
        session.addInput(replacement)
        input = replacement
        device = other
        neutralise()
        do throws(LensCheckFailure) {
            if let format { try apply(format, to: other) }
        } catch {
            session.commitConfiguration()
            throw error
        }
        session.commitConfiguration()
        preparePixelFormat()
    }

    // MARK: Manual. Each returns why the camera refused, or nil when the value was set.

    func setCustomExposure() throws(LensCheckFailure) -> String? {
        guard device.isExposureModeSupported(.custom) else { return "isExposureModeSupported(.custom) is false" }
        let active = device.activeFormat
        let duration = max(active.minExposureDuration, min(active.maxExposureDuration, CMTime(value: 1, timescale: 120)))
        let iso = min(active.maxISO, max(active.minISO, active.minISO * 4))
        guard active.supportsExposureModeCustom(lensAperture: AVCaptureDevice.currentLensAperture, duration: duration, iso: iso) else {
            return "the format does not support custom exposure at \(duration.seconds) s, ISO \(iso)"
        }
        try lock()
        defer { device.unlockForConfiguration() }
        device.setExposureModeCustom(duration: duration, iso: iso, completionHandler: nil)
        return nil
    }

    func setLockedWhiteBalance() throws(LensCheckFailure) -> String? {
        guard device.isWhiteBalanceModeSupported(.locked) else { return "isWhiteBalanceModeSupported(.locked) is false" }
        guard device.isLockingWhiteBalanceWithCustomDeviceGainsSupported else { return "isLockingWhiteBalanceWithCustomDeviceGainsSupported is false" }
        let asked = device.deviceWhiteBalanceGains(for: AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(temperature: 4000, tint: 0))
        let maxGain = device.maxWhiteBalanceGain
        let clamp = { (gain: Float) in min(maxGain, max(1, gain)) }
        let gains = AVCaptureDevice.WhiteBalanceGains(redGain: clamp(asked.redGain), greenGain: clamp(asked.greenGain), blueGain: clamp(asked.blueGain))
        try lock()
        defer { device.unlockForConfiguration() }
        device.setWhiteBalanceModeLocked(with: gains, completionHandler: nil)
        return nil
    }

    func setLockedFocus() throws(LensCheckFailure) -> String? {
        guard device.isFocusModeSupported(.locked) else { return "isFocusModeSupported(.locked) is false" }
        guard device.isLockingFocusWithCustomLensPositionSupported else { return "isLockingFocusWithCustomLensPositionSupported is false" }
        try lock()
        defer { device.unlockForConfiguration() }
        device.setFocusModeLocked(lensPosition: 0.3, completionHandler: nil)
        return nil
    }

    func resetManual() throws(LensCheckFailure) {
        try lock()
        defer { device.unlockForConfiguration() }
        if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
        if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) { device.whiteBalanceMode = .continuousAutoWhiteBalance }
        if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
    }

    // MARK: Reads

    /// What the camera says now: lens, zoom, exposure, white balance and focus, for the combined camera and for its active lens.
    func state() -> [String: String] {
        var values = Self.manualState(of: device, prefix: "")
        values["zoom"] = String(Double(device.videoZoomFactor))
        values["zoom range available"] = "\(device.minAvailableVideoZoomFactor)...\(device.maxAvailableVideoZoomFactor)"
        values["lens"] = lensName
        values["switching behaviour"] = Self.name(device.primaryConstituentDeviceSwitchingBehavior)
        values["switching behaviour active"] = Self.name(device.activePrimaryConstituentDeviceSwitchingBehavior)
        values["fallback lenses"] = device.fallbackPrimaryConstituentDevices.map { Self.name($0) }.joined(separator: ", ")
        if let active = device.activePrimaryConstituent {
            values.merge(Self.manualState(of: active, prefix: "active lens: ")) { _, new in new }
        }
        if let frame = tap.last {
            values["last frame"] = "f/\(frame.aperture.map { String($0) } ?? "?"), \(frame.exposureSeconds.map { String($0 * 1000) } ?? "?") ms, ISO \(frame.iso.map { String($0) } ?? "?")"
        }
        return values
    }

    static func manualState(of device: AVCaptureDevice, prefix: String) -> [String: String] {
        var values: [String: String] = [:]
        values[prefix + "supports custom exposure"] = String(device.isExposureModeSupported(.custom))
        values[prefix + "supports custom white balance gains"] = String(device.isLockingWhiteBalanceWithCustomDeviceGainsSupported)
        values[prefix + "supports custom lens position"] = String(device.isLockingFocusWithCustomLensPositionSupported)
        values[prefix + "exposure mode"] = String(device.exposureMode.rawValue)
        values[prefix + "exposure ms"] = String(device.exposureDuration.seconds * 1000)
        values[prefix + "ISO"] = String(device.iso)
        values[prefix + "ISO range"] = "\(device.activeFormat.minISO)...\(device.activeFormat.maxISO)"
        values[prefix + "aperture"] = String(device.lensAperture)
        values[prefix + "white balance mode"] = String(device.whiteBalanceMode.rawValue)
        let gains = device.deviceWhiteBalanceGains
        values[prefix + "white balance gains"] = "\(gains.redGain) \(gains.greenGain) \(gains.blueGain)"
        // The conversion raises for a gain outside 1...maxWhiteBalanceGain (AVCaptureDevice.h).
        let maxGain = device.maxWhiteBalanceGain
        if [gains.redGain, gains.greenGain, gains.blueGain].allSatisfy({ $0 >= 1 && $0 <= maxGain }) {
            let kelvin = device.temperatureAndTintValues(for: gains)
            values[prefix + "white balance kelvin and tint"] = "\(kelvin.temperature) \(kelvin.tint)"
        }
        values[prefix + "focus mode"] = String(device.focusMode.rawValue)
        values[prefix + "lens position"] = String(device.lensPosition)
        return values
    }

    /// What the photo output offers now.
    func photoFacts() -> [String: String] {
        var values: [String: String] = [:]
        values["preset"] = session.sessionPreset.rawValue
        values["lens"] = lensName
        values["zoom"] = String(Double(device.videoZoomFactor))
        values["active format"] = Self.describe(device.activeFormat)
        values["format photo sizes"] = device.activeFormat.supportedMaxPhotoDimensions.map { "\($0.width)x\($0.height)" }.joined(separator: " ")
        values["output largest photo"] = "\(photoOutput.maxPhotoDimensions.width)x\(photoOutput.maxPhotoDimensions.height)"
        values["raw pixel formats"] = photoOutput.availableRawPhotoPixelFormatTypes.map { type in
            let kind = AVCapturePhotoOutput.isBayerRAWPixelFormat(type) ? "Bayer" : AVCapturePhotoOutput.isAppleProRAWPixelFormat(type) ? "ProRAW" : "other"
            return "\(LensCheckTap.fourCC(type)) (\(kind))"
        }.joined(separator: ", ")
        values["raw file types"] = photoOutput.availableRawPhotoFileTypes.map(\.rawValue).joined(separator: " ")
        values["photo codecs"] = photoOutput.availablePhotoCodecTypes.map(\.rawValue).joined(separator: " ")
        values["ProRAW supported"] = String(photoOutput.isAppleProRAWSupported)
        values["photos from each lens supported"] = String(photoOutput.isVirtualDeviceConstituentPhotoDeliverySupported)
        values["lens fusion supported"] = String(photoOutput.isVirtualDeviceFusionSupported)
        return values
    }

    static func name(_ device: AVCaptureDevice?) -> String {
        switch device?.deviceType {
        case .builtInUltraWideCamera?: "ultra wide"
        case .builtInWideAngleCamera?: "wide"
        case .builtInDualWideCamera?: "dual wide"
        case let other?: other.rawValue
        case nil: "none"
        }
    }

    static func name(_ behaviour: AVCaptureDevice.PrimaryConstituentDeviceSwitchingBehavior) -> String {
        switch behaviour {
        case .unsupported: "unsupported"
        case .auto: "auto"
        case .restricted: "restricted"
        case .locked: "locked"
        @unknown default: "unknown \(behaviour.rawValue)"
        }
    }

    static func name(_ space: AVCaptureColorSpace) -> String {
        switch space {
        case .sRGB: "sRGB"
        case .P3_D65: "P3"
        case .HLG_BT2020: "HLG BT.2020"
        case .appleLog: "Apple Log"
        default: "colour space \(space.rawValue)"
        }
    }

    static func describe(_ format: AVCaptureDevice.Format) -> String {
        let size = format.formatDescription.dimensions
        let rates = format.videoSupportedFrameRateRanges.map { "\($0.minFrameRate)-\($0.maxFrameRate)" }.joined(separator: " ")
        return "\(size.width)x\(size.height) \(LensCheckTap.fourCC(format.formatDescription.mediaSubType.rawValue)) \(rates) fps\(format.isVideoBinned ? " binned" : "")"
    }

    // MARK: Session set-up

    private func lock() throws(LensCheckFailure) {
        do {
            try device.lockForConfiguration()
        } catch {
            throw LensCheckFailure(message: "The camera could not be locked: \(error.localizedDescription)")
        }
    }

    private func add(_ output: AVCaptureOutput, name: String) throws(LensCheckFailure) {
        guard session.canAddOutput(output) else { throw LensCheckFailure(message: "The session cannot take the \(name) output with \(device.localizedName)") }
        session.addOutput(output)
    }

    /// Buffers in the sensor's own orientation, unmirrored, as the app's data outputs have them.
    private func neutralise() {
        guard let connection = dataOutput.connection(with: .video) else { return }
        if connection.videoRotationAngle != 0, connection.isVideoRotationAngleSupported(0) { connection.videoRotationAngle = 0 }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
        }
    }

    /// The same choice `CameraSession.applyVideo` makes: the size, the colour space and a range that holds the rate, not
    /// binned when there is a choice.
    private func apply(_ wanted: LensCheckFormat, to device: AVCaptureDevice) throws(LensCheckFailure) {
        let space: AVCaptureColorSpace = wanted.isHLG ? .HLG_BT2020 : .sRGB
        let rate = Double(wanted.framesPerSecond)
        let candidates = device.formats.filter { format in
            let size = format.formatDescription.dimensions
            return size.width == wanted.width && size.height == wanted.height && format.supportedColorSpaces.contains(space)
                && format.videoSupportedFrameRateRanges.contains { $0.minFrameRate <= rate && rate <= $0.maxFrameRate }
        }
        guard let format = candidates.first(where: { !$0.isVideoBinned }) ?? candidates.first else {
            throw LensCheckFailure(message: "\(device.localizedName) has no format for \(wanted.label)")
        }
        do {
            try device.lockForConfiguration()
        } catch {
            throw LensCheckFailure(message: "The camera could not be locked: \(error.localizedDescription)")
        }
        defer { device.unlockForConfiguration() }
        device.activeFormat = format
        device.activeColorSpace = space
        let duration = CMTime(value: 1, timescale: CMTimeScale(wanted.framesPerSecond))
        device.activeVideoMinFrameDuration = duration
        device.activeVideoMaxFrameDuration = duration
    }

    /// The writer path's pixel format, set after the commit that set the camera's format, in a configuration change of its own
    /// (`CameraSession.preparePixelFormat`): 10-bit `x420` for HLG, 8-bit `420v` otherwise.
    private func preparePixelFormat() {
        guard let format else { return }
        let wanted = format.isHLG ? kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        let isOffered = dataOutput.availableVideoPixelFormatTypes.contains(wanted)
        setup["data output offers \(LensCheckTap.fourCC(wanted))"] = String(isOffered)
        guard isOffered else { return }
        session.beginConfiguration()
        dataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: wanted]
        session.commitConfiguration()
    }

    private func observe(_ device: AVCaptureDevice) {
        guard device.isVirtualDevice else { return }
        let tap = tap
        observations = [
            device.observe(\.activePrimaryConstituent, options: [.new]) { device, _ in
                tap.noteLens(Self.name(device.activePrimaryConstituent))
            },
            device.observe(\.isRampingVideoZoom, options: [.new]) { device, _ in
                if !device.isRampingVideoZoom { tap.noteRampEnded() }
            },
        ]
    }
}
