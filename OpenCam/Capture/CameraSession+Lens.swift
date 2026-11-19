import AVFoundation

/// The combined back camera's lens changes: a lens lock and a zoom on the camera the session already runs.
extension CameraSession {
    /// A lens button inside the combined camera is a lock and a zoom when the session runs it already, nothing else differs, the
    /// lens does (an identical configuration asked for again, as by a restart, is a full configure and writes no false lens
    /// line), and the active format reaches the new zoom (a format picked for another lens's zoom falls back to the full
    /// configure, which picks a format by zoom).
    func canChangeLensOnly(to configuration: SessionConfiguration, from previous: SessionConfiguration) -> Bool {
        guard session.isRunning, let device = videoInput?.device, device.uniqueID == configuration.combined?.deviceUniqueID,
              configuration.lens != previous.lens, configuration.changesOnlyLens(from: previous),
              CGFloat(configuration.zoomFactor) <= device.activeFormat.videoMaxZoomFactor else { return false }
        return true
    }

    /// Changes lens with no session configuration, so no frame is missed (measured 2026-11-16: the longest gap is one frame; the
    /// wide lens's first frame comes about 260 ms after the call at 30 fps, the ultra wide's about 70 ms). The camera returns
    /// to automatic, as after every configure.
    func changeLens(_ configuration: SessionConfiguration, from previous: SessionConfiguration) throws(CameraSessionError) {
        guard let device = videoInput?.device else { throw .deviceMissing(lensID: configuration.lens.id) }
        let start = ContinuousClock.now
        do {
            try device.lockForConfiguration()
        } catch {
            throw .lockFailed(reason: String(describing: error))
        }
        do throws(CameraSessionError) {
            try lockLens(configuration, on: device)
        } catch {
            device.unlockForConfiguration()
            throw error
        }
        device.unlockForConfiguration()
        settleZoom(configuration, on: device)
        resetManual()
        TimingJournal.lensChange(to: configuration, from: previous, since: start)
    }

    /// Caller holds the configuration lock. Locks the combined camera to the lens's own camera, so the button decides the lens
    /// and never the scene: with the default switching the camera kept the ultra wide lens at 1x in four of five sessions
    /// (measured 2026-11-16). The lock moves the zoom into the lens's range by itself; the zoom asked for is set here when the
    /// range already holds it, else by `settleZoom`.
    func lockLens(_ configuration: SessionConfiguration, on device: AVCaptureDevice) throws(CameraSessionError) {
        guard device.isPrimaryConstituentDeviceSwitchingBehaviorLockedWithDeviceSupported,
              let lensDevice = device.constituentDevices.first(where: { $0.uniqueID == configuration.lens.deviceUniqueID }) else {
            throw .deviceMissing(lensID: configuration.lens.id)
        }
        if device.primaryConstituentDeviceSwitchingBehavior != .locked || device.activePrimaryConstituent?.uniqueID != lensDevice.uniqueID {
            device.setPrimaryConstituentDeviceSwitchingBehaviorLockedWith(lensDevice)
        }
        let zoom = targetZoom(for: configuration, on: device)
        if zoom >= device.minAvailableVideoZoomFactor, zoom <= device.maxAvailableVideoZoomFactor {
            device.videoZoomFactor = zoom
        }
    }

    /// Sets the configuration's zoom on the combined camera when the lock left it elsewhere. After a lock to the ultra wide lens
    /// the zoom range took 6 to 33 ms to open below the wide lens's (measured 2026-11-16). A zoom below the range is clamped to it
    /// (AVCaptureDevice.h, `minAvailableVideoZoomFactor`), which would leave the ultra wide lens cropped to the wide lens's framing,
    /// and one above the format's maximum raises an exception Swift cannot catch. So this waits for the range, at most a quarter
    /// second and only while the session runs, and otherwise leaves the zoom where the lock put it; `restoreLens` tries again
    /// once the session has started. Callers hold no configuration lock: the range was measured to move after the lock was released.
    func settleZoom(_ configuration: SessionConfiguration, on device: AVCaptureDevice) {
        guard configuration.combined != nil else { return }
        let zoom = targetZoom(for: configuration, on: device)
        guard device.videoZoomFactor != zoom else { return }
        let isHeld = { zoom >= device.minAvailableVideoZoomFactor && zoom <= device.maxAvailableVideoZoomFactor }
        let deadline = ContinuousClock.now + .milliseconds(250)
        while session.isRunning, !isHeld(), ContinuousClock.now < deadline {
            Thread.sleep(forTimeInterval: 0.002)
        }
        guard isHeld() else {
            // Before the session runs the range cannot open; `restoreLens` sets the zoom once it has started (a launch on 0.5x).
            guard session.isRunning else { return }
            Self.logger.error("[CameraSession:settleZoom] The zoom range does not hold the lens's zoom — {lens: \(configuration.lens.id, privacy: .public), zoom: \(Double(zoom)), min: \(Double(device.minAvailableVideoZoomFactor)), running: \(self.session.isRunning)}")
            return
        }
        do {
            try device.lockForConfiguration()
        } catch {
            Self.logger.error("[CameraSession:settleZoom] Cannot lock the camera for configuration — {lens: \(configuration.lens.id, privacy: .public), reason: \(String(describing: error), privacy: .public)}")
            return
        }
        if isHeld() {
            device.videoZoomFactor = zoom
        }
        device.unlockForConfiguration()
    }

    /// Checks the combined camera against the configuration's lens once its own state can be read, and puts the lock and the
    /// zoom back where they differ. Whether a new format keeps the lock, and whether the zoom range moves before the session
    /// runs, were not measured, so this runs after every configure's commit, and again through `restoreLens`. It changes
    /// nothing on a camera already locked to the lens at its zoom. A failure is logged and never fails the configure: the
    /// camera then shows whatever lens the lock inside the configuration left.
    func confirmLens(_ configuration: SessionConfiguration, on device: AVCaptureDevice) {
        guard configuration.combined != nil else { return }
        do {
            try device.lockForConfiguration()
        } catch {
            Self.logger.error("[CameraSession:confirmLens] Cannot lock the camera for configuration — {lens: \(configuration.lens.id, privacy: .public), reason: \(String(describing: error), privacy: .public)}")
            return
        }
        do throws(CameraSessionError) {
            try lockLens(configuration, on: device)
        } catch {
            Self.logger.error("\(error.description, privacy: .public)")
        }
        device.unlockForConfiguration()
        settleZoom(configuration, on: device)
    }

    /// On the combined camera the movie output would replace the lens lock with its own switching rule while it records unless
    /// this is off (AVCaptureFileOutput.h:538; measured 2026-11-16: left on, the active behaviour while recording was "restricted").
    /// The output turns it on when it connects to such a camera, so it is turned off after a configure's commits, on the
    /// connected output, as measured, and checked again before each recording.
    func keepLensLockWhileRecording(_ configuration: SessionConfiguration) {
        guard configuration.combined != nil, session.outputs.contains(recorder.output),
              recorder.output.isPrimaryConstituentDeviceSwitchingBehaviorForRecordingEnabled else { return }
        recorder.output.isPrimaryConstituentDeviceSwitchingBehaviorForRecordingEnabled = false
    }

    /// `confirmLens` for the applied configuration: after a start, when the zoom could not be set before the session ran, and
    /// after a restart, when the camera may have come back unlocked.
    func restoreLens() {
        guard let applied = lastWorkingConfiguration, let device = videoInput?.device else { return }
        confirmLens(applied, on: device)
        restorePinch(applied, on: device)
    }
}
