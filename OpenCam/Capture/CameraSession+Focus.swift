import AVFoundation
import OSLog

/// Setting the focus and exposure point. Every decision is `FocusPlan`'s, made from the device's support and the settings last
/// applied by hand; this only reads support, locks the device and forwards each field the plan holds. Never configures the
/// session, so it works while recording. A point is set before its mode, because the mode starts the operation (AVCaptureDevice.h).
extension CameraSession {
    /// Runs the plan for `request` on the current camera. `.nothing` without a running session or camera, or when the plan is empty.
    func applyFocus(_ request: FocusRequest) -> FocusOutcome {
        guard session.isRunning, let device = videoInput?.device else {
            removeSubjectAreaObserver()
            return .nothing
        }
        let plan = FocusPlan.make(request, manual: appliedManual, support: focusSupport(of: device))
        // An empty plan has nothing to set; it only has to end a watch an earlier request left on.
        guard plan.outcome != .nothing || subjectAreaObserver != nil else { return .nothing }
        do {
            try device.lockForConfiguration()
        } catch {
            Self.logger.error("[CameraSession:applyFocus] Cannot lock the camera for configuration — {lens: \(self.lastWorkingConfiguration?.lens.id ?? "unknown", privacy: .public), reason: \(String(describing: error), privacy: .public)}")
            return .nothing
        }
        defer { device.unlockForConfiguration() }
        if let point = plan.focusPoint, let mode = plan.focusMode {
            device.focusPointOfInterest = Self.devicePoint(point)
            device.focusMode = mode == .once ? .autoFocus : .continuousAutoFocus
        }
        if let point = plan.exposurePoint, let mode = plan.exposureMode {
            device.exposurePointOfInterest = Self.devicePoint(point)
            device.exposureMode = mode == .once ? .autoExpose : .continuousAutoExposure
        }
        device.isSubjectAreaChangeMonitoringEnabled = plan.watchesSubjectArea
        if case .recentre = request {
            didMoveFocusPoint = false
        } else if plan.outcome != .nothing {
            didMoveFocusPoint = true
        }
        removeSubjectAreaObserver()
        if plan.watchesSubjectArea {
            subjectAreaObserver = Self.observeSubjectArea(of: device, owner: self)
        }
        return plan.outcome
    }

    /// The caller holds the configuration lock, and calls this before the continuous modes are set. Touches the device only after a
    /// tap or hold moved the point, so a configure with no gesture changes nothing, whatever the device did by itself.
    func resetFocusPoint(on device: AVCaptureDevice) {
        guard didMoveFocusPoint else { return }
        didMoveFocusPoint = false
        let centre = Self.devicePoint(.centre)
        if device.isFocusPointOfInterestSupported { device.focusPointOfInterest = centre }
        if device.isExposurePointOfInterestSupported { device.exposurePointOfInterest = centre }
        device.isSubjectAreaChangeMonitoringEnabled = false
        removeSubjectAreaObserver()
    }

    /// The scene changed while a tap's watch was on: back to the centre, which also ends the watch.
    func subjectAreaChanged() {
        guard subjectAreaObserver != nil else { return }
        _ = applyFocus(.recentre)
    }

    private func removeSubjectAreaObserver() {
        guard let observer = subjectAreaObserver else { return }
        NotificationCenter.default.removeObserver(observer)
        subjectAreaObserver = nil
    }

    private func focusSupport(of device: AVCaptureDevice) -> FocusSupport {
        FocusSupport(
            focusPoint: device.isFocusPointOfInterestSupported,
            exposurePoint: device.isExposurePointOfInterestSupported,
            autoFocusOnce: device.isFocusModeSupported(.autoFocus),
            continuousFocus: device.isFocusModeSupported(.continuousAutoFocus),
            autoExposeOnce: device.isExposureModeSupported(.autoExpose),
            continuousExposure: device.isExposureModeSupported(.continuousAutoExposure))
    }

    /// Clamped: a point outside 0...1 is not taken from the camera's own picture.
    private static func devicePoint(_ point: FocusPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, 0), 1), y: min(max(point.y, 0), 1))
    }

    private nonisolated static func observeSubjectArea(of device: AVCaptureDevice, owner: CameraSession) -> any NSObjectProtocol {
        NotificationCenter.default.addObserver(forName: AVCaptureDevice.subjectAreaDidChangeNotification, object: device, queue: nil) { [weak owner] _ in
            Task { await owner?.subjectAreaChanged() }
        }
    }
}
