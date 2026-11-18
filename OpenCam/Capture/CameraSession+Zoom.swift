import AVFoundation
import OSLog

/// Pinch to zoom within the lens. The pinch is a factor on the configuration's own zoom (`PinchZoom`), kept in `pinch` so every
/// place that sets the zoom (a configure, the lens lock, `settleZoom`, a restart's `restoreLens`) sets the same number through
/// `targetZoom`, and a pinch survives all of them. With `pinch` at 1 that number is the configuration's zoom, as before.
extension CameraSession {
    /// Sets the lens-relative pinch with a ramp and keeps it for every later re-apply. Returns the pinch the camera can hold: the
    /// active format may stop short of the cap. Never configures; works while recording. The pinch is stored first, so a configure
    /// or restart later applies it even when nothing runs now. This is its own actor turn, so it can never land between
    /// `lockLens` and `settleZoom`, which `changeLens` and `confirmLens` run in one turn.
    func applyZoom(pinch: Double) -> Double {
        if pinch.isFinite { self.pinch = min(max(pinch, 1), PinchZoom.cap) }
        guard let configuration = lastWorkingConfiguration, session.isRunning, let device = videoInput?.device else {
            return self.pinch
        }
        let target = targetZoom(for: configuration, on: device)
        let held = Double(target) / configuration.zoomFactor
        self.pinch = held
        do {
            try device.lockForConfiguration()
        } catch {
            Self.logger.error("[CameraSession:applyZoom] Cannot lock the camera for configuration — {lens: \(configuration.lens.id, privacy: .public), reason: \(String(describing: error), privacy: .public)}")
            return held
        }
        defer { device.unlockForConfiguration() }
        // Outside the available range the lens lock's range is still moving: `settleZoom` or `restoreLens` sets the zoom.
        if target >= device.minAvailableVideoZoomFactor, target <= device.maxAvailableVideoZoomFactor {
            device.ramp(toVideoZoomFactor: target, withRate: PinchZoom.rampRate)
        }
        return held
    }

    /// The zoom every setter puts on `device` for `configuration`: its own zoom times the pinch, within the active format.
    /// Never clamped to the available range here: `settleZoom` waits for the range to hold this very number.
    func targetZoom(for configuration: SessionConfiguration, on device: AVCaptureDevice) -> CGFloat {
        CGFloat(PinchZoom.target(base: configuration.zoomFactor, pinch: pinch,
                                 formatMax: Double(device.activeFormat.videoMaxZoomFactor)))
    }

    /// The own camera's zoom after a start or restart, when a pinch is on. The combined camera is `confirmLens`'s. Takes the
    /// configuration lock itself and sets the zoom only inside the available range.
    func restorePinch(_ configuration: SessionConfiguration, on device: AVCaptureDevice) {
        guard configuration.combined == nil, pinch != 1 else { return }
        let target = targetZoom(for: configuration, on: device)
        guard device.videoZoomFactor != target, target >= device.minAvailableVideoZoomFactor,
              target <= device.maxAvailableVideoZoomFactor else { return }
        do {
            try device.lockForConfiguration()
        } catch {
            Self.logger.error("[CameraSession:restorePinch] Cannot lock the camera for configuration — {lens: \(configuration.lens.id, privacy: .public), reason: \(String(describing: error), privacy: .public)}")
            return
        }
        device.videoZoomFactor = target
        device.unlockForConfiguration()
    }
}
