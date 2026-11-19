import AVFoundation
import OSLog

/// Pinch to zoom within the lens. The pinch is a factor on the configuration's own zoom (`PinchZoom`), kept in `pinch` so every
/// place that sets the zoom (a configure, the lens lock, `settleZoom`, a restart's `restoreLens`) sets the same number through
/// `targetZoom`, and a pinch survives all of them. With `pinch` at 1 that number is the configuration's zoom, as before.
extension CameraSession {
    /// Called by `configure` for the configuration it applies: the pinch goes back to 1 unless only a look, sound, recorder or
    /// combined-camera difference separates it from the one the pinch was last decided for. That one is not the last working
    /// configuration, which a release for the Library forgets, so a visit to the Library keeps the pinch.
    func settlePinch(for configuration: SessionConfiguration) {
        if !PinchZoom.keeps(from: pinchConfiguration, to: configuration) { pinch = 1 }
        pinchConfiguration = configuration
    }

    /// Sets the lens-relative pinch with a ramp and keeps it for every later re-apply. Returns the pinch the camera can hold: the
    /// active format may stop short of the cap, and so may the available range. Never configures; works while recording. The
    /// pinch is stored first, so a configure or restart later applies it even when nothing runs now. This is its own actor turn,
    /// so it can never land between `lockLens` and `settleZoom`, which `changeLens` and `confirmLens` run in one turn.
    func applyZoom(pinch: Double) -> Double {
        if pinch.isFinite { self.pinch = min(max(pinch, 1), PinchZoom.cap) }
        guard let configuration = lastWorkingConfiguration, session.isRunning, let device = videoInput?.device else {
            return self.pinch
        }
        // Held only inside the available range: below it the lens lock's range is still moving and `settleZoom` or `restoreLens`
        // sets the zoom, so nothing changes here; the top of the range stops the pinch.
        let target = Double(targetZoom(for: configuration, on: device))
        guard let held = PinchZoom.held(target: target, availableMin: Double(device.minAvailableVideoZoomFactor),
                                        availableMax: Double(device.maxAvailableVideoZoomFactor)) else { return self.pinch }
        self.pinch = max(held / configuration.zoomFactor, 1)
        guard device.videoZoomFactor != CGFloat(held) else { return self.pinch }
        do {
            try device.lockForConfiguration()
        } catch {
            Self.logger.error("[CameraSession:applyZoom] Cannot lock the camera for configuration — {lens: \(configuration.lens.id, privacy: .public), reason: \(String(describing: error), privacy: .public)}")
            return self.pinch
        }
        device.ramp(toVideoZoomFactor: CGFloat(held), withRate: PinchZoom.rampRate)
        device.unlockForConfiguration()
        return self.pinch
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
