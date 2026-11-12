import AVFoundation
import CoreMedia
import OSLog

/// The session's manual surface. Every decision (what to set, and every number clamped) is made in `ManualApplyPlan` as plain
/// values; the code here runs a plan, repeating the device's own clamp on the plan's numbers, because a value outside the
/// device's limits raises an exception Swift cannot catch. Nothing here waits for a completion handler: the model's coalescer
/// keeps one apply in flight.
extension CameraSession {
    /// What the current camera and its active format allow by hand; nil while the session is stopped or holds no camera.
    func manualRanges() -> ManualRanges? {
        guard session.isRunning, let device = videoInput?.device else { return nil }
        return ranges(of: device)
    }

    /// Sets the camera to `settings`, changing only the groups that differ from the last settings applied to this camera.
    /// Returns the settings actually set, which differ from the plan's only where a white balance gain was clamped.
    func applyManual(_ settings: ManualSettings, reapplyingAll: Bool) throws(ManualControlError) -> ManualSettings {
        guard session.isRunning, let device = videoInput?.device else { throw .noCamera }
        let limits = ranges(of: device)
        let plan = try ManualApplyPlan.make(settings, applied: reapplyingAll ? nil : appliedManual, limits: limits,
                                            lens: lastWorkingConfiguration?.lens.id ?? "unknown", isRAWClipRecording: isRAWClipRecording)
        do {
            try device.lockForConfiguration()
        } catch {
            throw .lockFailed(reason: String(describing: error))
        }
        defer { device.unlockForConfiguration() }
        var result = plan.applied
        if let exposure = plan.exposure {
            if !setExposure(exposure, restoresFrameDuration: plan.restoresFrameDuration, on: device) {
                // Not set, so the camera still has the exposure it had.
                result.exposure = appliedManual?.exposure ?? .automatic
            }
        }
        if let bias = plan.bias {
            let low = device.minExposureTargetBias, high = device.maxExposureTargetBias
            let value = ManualApplyPlan.clampedValue(bias, lower: low, upper: high)
            if value != bias { logClamp("bias", asked: Double(bias), set: Double(value)) }
            device.setExposureTargetBias(value, completionHandler: nil)
        }
        if let whiteBalance = plan.whiteBalance, let reported = setWhiteBalance(whiteBalance, on: device) {
            result.whiteBalance = reported
        }
        if let focus = plan.focus {
            setFocus(focus, on: device)
        }
        // What the camera took, not what was asked: a clamped white balance is then not locked again by the next apply.
        appliedManual = result
        if plan.exposure != nil {
            setExposureBiasControls(enabled: CameraControlPlan.enablesExposureBias(for: plan.applied.exposure))
        }
        return result
    }

    /// Returns the camera to automatic after a configure or a restart: continuous exposure, bias 0, continuous white balance and
    /// continuous autofocus, each behind its support check, and forgets what was applied. Does nothing without a camera.
    /// A lock failure is logged and never fails the configure.
    func resetManual() {
        appliedManual = nil
        guard let device = videoInput?.device else { return }
        do {
            try device.lockForConfiguration()
        } catch {
            Self.logger.error("[CameraSession:resetManual] Cannot lock the camera for configuration — {lens: \(self.lastWorkingConfiguration?.lens.id ?? "unknown", privacy: .public), reason: \(String(describing: error), privacy: .public)}")
            return
        }
        defer { device.unlockForConfiguration() }
        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
        }
        // Bias 0 is inside the device's limits only when they bracket it (AVCaptureDevice.h: the setter raises otherwise).
        if device.minExposureTargetBias <= 0, device.maxExposureTargetBias >= 0 {
            device.setExposureTargetBias(0, completionHandler: nil)
        }
        if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
            device.whiteBalanceMode = .continuousAutoWhiteBalance
        }
        if device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusMode = .continuousAutoFocus
        }
        setExposureBiasControls(enabled: true)
    }

    /// The Camera Control's exposure bias sliders follow whether exposure is automatic.
    private func setExposureBiasControls(enabled isEnabled: Bool) {
        for control in session.controls {
            guard let slider = control as? AVCaptureSystemExposureBiasSlider else { continue }
            slider.isEnabled = isEnabled
        }
    }

    // MARK: Limits

    /// From what the session has attached: video mode has the movie output.
    private var isVideoMode: Bool { session.outputs.contains(recorder.output) }

    /// The table of limits, read off the device. Custom exposure needs `isExposureModeSupported(.custom)`; in video the
    /// shutter's upper end is the frame time, and `frameSeconds` is set (photo mode has no frame time).
    private func ranges(of device: AVCaptureDevice) -> ManualRanges {
        let format = device.activeFormat
        var ranges = ManualRanges()
        ranges.isVideo = isVideoMode
        if ranges.isVideo {
            let frame = device.activeVideoMaxFrameDuration
            if frame.isNumeric, frame.seconds > 0 { ranges.frameSeconds = frame.seconds }
        }
        let shortest = format.minExposureDuration, longest = format.maxExposureDuration
        if device.isExposureModeSupported(.custom), shortest.isNumeric, longest.isNumeric, shortest.seconds > 0,
           format.minISO.isFinite, format.maxISO.isFinite, format.minISO <= format.maxISO {
            var upper = longest.seconds
            if let frame = ranges.frameSeconds { upper = min(upper, frame) }
            ranges.shutterSeconds = shortest.seconds...max(shortest.seconds, upper)
            ranges.iso = format.minISO...format.maxISO
        }
        if let recommended = format.systemRecommendedExposureBiasRange {
            ranges.bias = recommended
        } else if device.minExposureTargetBias.isFinite, device.maxExposureTargetBias.isFinite,
                  device.minExposureTargetBias <= device.maxExposureTargetBias {
            ranges.bias = device.minExposureTargetBias...device.maxExposureTargetBias
        }
        ranges.hasWhiteBalance = device.isLockingWhiteBalanceWithCustomDeviceGainsSupported
            && device.isWhiteBalanceModeSupported(.locked) && device.maxWhiteBalanceGain.isFinite && device.maxWhiteBalanceGain >= 1
        ranges.hasFocus = device.isFocusModeSupported(.locked) && device.isLockingFocusWithCustomLensPositionSupported
        return ranges
    }

    // MARK: Device calls. The caller holds the configuration lock.

    /// Returns whether the exposure was set.
    private func setExposure(_ exposure: ManualApplyPlan.Exposure, restoresFrameDuration: Bool, on device: AVCaptureDevice) -> Bool {
        // Setting the frame duration throws while auto video frame rate is on (AVCaptureDevice.h, activeVideoMaxFrameDuration).
        if restoresFrameDuration, !device.isAutoVideoFrameRateEnabled {
            device.activeVideoMaxFrameDuration = .invalid
        }
        switch exposure {
        case .continuous:
            guard device.isExposureModeSupported(.continuousAutoExposure) else { return false }
            device.exposureMode = .continuousAutoExposure
            return true
        case .custom(let seconds, let iso):
            guard device.isExposureModeSupported(.custom) else {
                Self.logger.error("[CameraSession:applyManual] Custom exposure not supported — {lens: \(self.lastWorkingConfiguration?.lens.id ?? "unknown", privacy: .public)}")
                return false
            }
            let format = device.activeFormat
            var longest = format.maxExposureDuration
            if isVideoMode, device.activeVideoMaxFrameDuration.isNumeric { longest = min(longest, device.activeVideoMaxFrameDuration) }
            let duration = seconds.flatMap { ManualApplyPlan.clampedDuration($0, minimum: format.minExposureDuration, maximum: longest) }
            // Logged only when the clamp moved the CMTime itself.
            if let seconds, let duration, duration != CMTime(seconds: seconds, preferredTimescale: 1_000_000_000) {
                logClamp("shutter", asked: seconds, set: duration.seconds)
            }
            let sensitivity = iso.map { ManualApplyPlan.clampedValue($0, lower: format.minISO, upper: format.maxISO) }
            if let iso, let sensitivity, sensitivity != iso { logClamp("iso", asked: Double(iso), set: Double(sensitivity)) }
            let durationToSet = duration ?? AVCaptureDevice.currentExposureDuration
            let isoToSet = sensitivity ?? AVCaptureDevice.currentISO
            // The setter raises for a combination the format does not support; the format can be asked with the exact values
            // (AVCaptureDevice.h, `supportsExposureModeCustom`, which accepts the "current" constants).
            guard format.supportsExposureModeCustom(lensAperture: AVCaptureDevice.currentLensAperture, duration: durationToSet, iso: isoToSet) else {
                Self.logger.error("[CameraSession:applyManual] Custom exposure not supported by the format — {lens: \(self.lastWorkingConfiguration?.lens.id ?? "unknown", privacy: .public), duration: \(durationToSet.seconds), iso: \(isoToSet)}")
                return false
            }
            device.setExposureModeCustom(duration: durationToSet, iso: isoToSet, completionHandler: nil)
            return true
        }
    }

    /// Returns the white balance actually set when a gain was clamped, else nil.
    private func setWhiteBalance(_ whiteBalance: ManualApplyPlan.WhiteBalance, on device: AVCaptureDevice) -> ManualSettings.WhiteBalance? {
        switch whiteBalance {
        case .continuous:
            guard device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) else { return nil }
            device.whiteBalanceMode = .continuousAutoWhiteBalance
        case .continuousAfterClip:
            // The clip keeps white balance locked; the mode returns when it ends (`restoreWhiteBalance`).
            guard device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) else { return nil }
            whiteBalanceRestore = (device, .continuousAutoWhiteBalance)
        case .locked(let kelvin, let tint):
            guard device.isLockingWhiteBalanceWithCustomDeviceGainsSupported, device.isWhiteBalanceModeSupported(.locked) else { return nil }
            // A clip's restore would undo what is set by hand now.
            whiteBalanceRestore = nil
            let maxGain = device.maxWhiteBalanceGain
            let asked = device.deviceWhiteBalanceGains(for: AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(temperature: kelvin, tint: tint))
            let gains = AVCaptureDevice.WhiteBalanceGains(redGain: ManualApplyPlan.clampedGain(asked.redGain, max: maxGain),
                                                          greenGain: ManualApplyPlan.clampedGain(asked.greenGain, max: maxGain),
                                                          blueGain: ManualApplyPlan.clampedGain(asked.blueGain, max: maxGain))
            device.setWhiteBalanceModeLocked(with: gains, completionHandler: nil)
            guard gains.redGain != asked.redGain || gains.greenGain != asked.greenGain || gains.blueGain != asked.blueGain else { return nil }
            // Only the clamped gains are converted back: the conversion raises for a gain outside 1...maxWhiteBalanceGain.
            let reported = device.temperatureAndTintValues(for: gains)
            logClamp("white balance", asked: Double(kelvin), set: Double(reported.temperature))
            return .manual(kelvin: reported.temperature, tint: reported.tint)
        }
        return nil
    }

    private func setFocus(_ focus: ManualApplyPlan.Focus, on device: AVCaptureDevice) {
        switch focus {
        case .continuous:
            guard device.isFocusModeSupported(.continuousAutoFocus) else { return }
            device.focusMode = .continuousAutoFocus
        case .locked(let position):
            guard device.isFocusModeSupported(.locked), device.isLockingFocusWithCustomLensPositionSupported else { return }
            device.setFocusModeLocked(lensPosition: ManualApplyPlan.clampedValue(position, lower: 0, upper: 1), completionHandler: nil)
        }
    }

    /// A value the device's own limits moved is logged, not thrown: the plan's clamp already made it a legal request.
    private func logClamp(_ control: String, asked: Double, set: Double) {
        Self.logger.notice("[CameraSession:applyManual] Value clamped to the device's limits — {control: \(control, privacy: .public), asked: \(asked), set: \(set)}")
    }
}
