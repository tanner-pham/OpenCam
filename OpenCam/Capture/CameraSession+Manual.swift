import AVFoundation
import CoreMedia
import OSLog

/// The session's manual surface. Every decision (what to set, every number clamped, what the device may be asked) is made in
/// tested code as plain values: `ManualApplyPlan` from the settings, `ManualRanges.make` and `ManualDeviceRequest.make` from the
/// `DeviceLimits` read off the camera here. The code below only reads limits, asks for a request, and forwards each field that
/// is present, because a value outside the device's limits raises an exception Swift cannot catch. Nothing here waits for a
/// completion handler: the model's coalescer keeps one apply in flight.
extension CameraSession {
    /// What the current camera and its active format allow by hand; nil while the session is stopped or holds no camera.
    func manualRanges() -> ManualRanges? {
        guard session.isRunning, let device = videoInput?.device else { return nil }
        return ManualRanges.make(from: deviceLimits(of: device))
    }

    /// Sets the camera to `settings`, changing only the groups that differ from the last settings applied to this camera.
    /// Returns the settings actually set.
    func applyManual(_ settings: ManualSettings, reapplyingAll: Bool) throws(ManualControlError) -> ManualSettings {
        guard session.isRunning, let device = videoInput?.device else { throw .noCamera }
        let limits = deviceLimits(of: device)
        let plan = try ManualApplyPlan.make(settings, applied: reapplyingAll ? nil : appliedManual, limits: ManualRanges.make(from: limits),
                                            lens: lensName, isRAWClipRecording: isRAWClipRecording)
        let request = ManualDeviceRequest.make(plan, limits: limits)
        do {
            try device.lockForConfiguration()
        } catch {
            throw .lockFailed(reason: String(describing: error))
        }
        defer { device.unlockForConfiguration() }
        let outcome = run(request, on: device)
        let result = ManualDeviceRequest.result(of: plan, previous: appliedManual, outcome: outcome)
        // What the camera took, not what was asked: a clamped white balance is then not locked again by the next apply.
        appliedManual = result
        if plan.exposure != nil {
            setExposureBiasControls(enabled: CameraControlPlan.enablesExposureBias(for: plan.applied.exposure))
        }
        return result
    }

    /// Returns the camera to automatic after a configure or a restart, and forgets what was applied. Does nothing without a
    /// camera. A lock failure is logged and never fails the configure.
    func resetManual() {
        appliedManual = nil
        guard let device = videoInput?.device else { return }
        let request = ManualDeviceRequest.resetting(deviceLimits(of: device))
        do {
            try device.lockForConfiguration()
        } catch {
            Self.logger.error("[CameraSession:resetManual] Cannot lock the camera for configuration — {lens: \(self.lensName, privacy: .public), reason: \(String(describing: error), privacy: .public)}")
            return
        }
        defer { device.unlockForConfiguration() }
        _ = run(request, on: device)
        setExposureBiasControls(enabled: true)
    }

    /// The Camera Control's exposure bias sliders follow whether exposure is automatic.
    private func setExposureBiasControls(enabled isEnabled: Bool) {
        for control in session.controls {
            guard let slider = control as? AVCaptureSystemExposureBiasSlider else { continue }
            slider.isEnabled = isEnabled
        }
    }

    private var lensName: String { lastWorkingConfiguration?.lens.id ?? "unknown" }

    // MARK: Device. Reads only.

    /// Video mode is what the session has attached: the movie output.
    private func deviceLimits(of device: AVCaptureDevice) -> DeviceLimits {
        let format = device.activeFormat
        return DeviceLimits(
            minExposureDuration: format.minExposureDuration, maxExposureDuration: format.maxExposureDuration,
            frameDuration: device.activeVideoMaxFrameDuration, minISO: format.minISO, maxISO: format.maxISO,
            minBias: device.minExposureTargetBias, maxBias: device.maxExposureTargetBias,
            recommendedBias: format.systemRecommendedExposureBiasRange, maxWhiteBalanceGain: device.maxWhiteBalanceGain,
            isVideo: session.outputs.contains(recorder.output), isAutoFrameRateEnabled: device.isAutoVideoFrameRateEnabled,
            supportsContinuousExposure: device.isExposureModeSupported(.continuousAutoExposure),
            supportsCustomExposure: device.isExposureModeSupported(.custom),
            supportsContinuousWhiteBalance: device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance),
            supportsLockedWhiteBalance: device.isWhiteBalanceModeSupported(.locked),
            supportsCustomGains: device.isLockingWhiteBalanceWithCustomDeviceGainsSupported,
            supportsContinuousFocus: device.isFocusModeSupported(.continuousAutoFocus),
            supportsLockedFocus: device.isFocusModeSupported(.locked),
            supportsCustomLensPosition: device.isLockingFocusWithCustomLensPositionSupported)
    }

    // MARK: Device. Forwards a request; the caller holds the configuration lock.

    private func run(_ request: ManualDeviceRequest, on device: AVCaptureDevice) -> ManualDeviceRequest.Outcome {
        for clamp in request.clamps {
            Self.logger.notice("[CameraSession:applyManual] Value clamped to the device's limits — {control: \(clamp.control, privacy: .public), asked: \(clamp.asked), set: \(clamp.set)}")
        }
        if request.resetsFrameDuration { device.activeVideoMaxFrameDuration = .invalid }
        var outcome = ManualDeviceRequest.Outcome(didSetExposure: false, whiteBalance: nil)
        switch request.exposure {
        case .continuous?:
            device.exposureMode = .continuousAutoExposure
            outcome.didSetExposure = true
        case .custom(let duration, let iso)?:
            let durationToSet = duration ?? AVCaptureDevice.currentExposureDuration
            let isoToSet = iso ?? AVCaptureDevice.currentISO
            // The setter also raises for a combination the format does not support, which the format answers for the exact
            // values (AVCaptureDevice.h, `supportsExposureModeCustom`, which accepts the "current" constants).
            if device.activeFormat.supportsExposureModeCustom(lensAperture: AVCaptureDevice.currentLensAperture, duration: durationToSet, iso: isoToSet) {
                device.setExposureModeCustom(duration: durationToSet, iso: isoToSet, completionHandler: nil)
                outcome.didSetExposure = true
            } else {
                Self.logger.error("[CameraSession:applyManual] Custom exposure not supported by the format — {lens: \(self.lensName, privacy: .public), duration: \(durationToSet.seconds), iso: \(isoToSet)}")
            }
        case nil:
            break
        }
        if let bias = request.bias {
            device.setExposureTargetBias(bias, completionHandler: nil)
        }
        switch request.whiteBalance {
        case .continuous?:
            device.whiteBalanceMode = .continuousAutoWhiteBalance
        case .locked(let kelvin, let tint, let maxGain)?:
            let asked = device.deviceWhiteBalanceGains(for: AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(temperature: kelvin, tint: tint))
            let clamped = ManualDeviceRequest.clampedGains(ManualDeviceRequest.Gains(red: asked.redGain, green: asked.greenGain, blue: asked.blueGain), max: maxGain)
            let gains = AVCaptureDevice.WhiteBalanceGains(redGain: clamped.gains.red, greenGain: clamped.gains.green, blueGain: clamped.gains.blue)
            device.setWhiteBalanceModeLocked(with: gains, completionHandler: nil)
            if clamped.wasClamped {
                // Only the clamped gains are converted back: the conversion raises for a gain outside 1...maxWhiteBalanceGain.
                let reported = device.temperatureAndTintValues(for: gains)
                outcome.whiteBalance = .manual(kelvin: reported.temperature, tint: reported.tint)
                Self.logger.notice("[CameraSession:applyManual] Value clamped to the device's limits — {control: white balance, asked: \(kelvin), set: \(reported.temperature)}")
            }
        case .stayLocked?, nil:
            break
        }
        switch request.restore {
        case .leave: break
        case .clear: whiteBalanceRestore = nil
        case .toContinuous: whiteBalanceRestore = (device, .continuousAutoWhiteBalance)
        }
        switch request.focus {
        case .continuous?: device.focusMode = .continuousAutoFocus
        case .locked(let position)?: device.setFocusModeLocked(lensPosition: position, completionHandler: nil)
        case nil: break
        }
        return outcome
    }
}
