import Foundation

/// What each state of the camera says, and which line wins when several apply. Pure, so the copy is tested without a screen.
nonisolated enum StatusText {
    static let microphoneOff = "No microphone access"
    static let storageFull = "Storage full"

    static func viewfinder(_ phase: CameraPhase) -> ViewfinderStatus? {
        switch phase {
        case .scanning: ViewfinderStatus(message: "Reading camera formats…", offersSettings: false)
        case .cameraDenied: ViewfinderStatus(message: "Camera access is off.", offersSettings: true)
        case .cameraRestricted: ViewfinderStatus(message: "Camera access is restricted on this iPhone.", offersSettings: false)
        case .failed(let message): ViewfinderStatus(message: message, offersSettings: false)
        // Released, the Library covers the camera; it comes back as the Library closes, so there is nothing to explain.
        case .ready, .simulator, .released: nil
        }
    }

    static func pressure(_ level: PressureLevel, isThermal: Bool) -> String? {
        let cause = isThermal ? "The phone is hot." : "The phone is under heavy load."
        switch level {
        case .nominal, .fair: return nil
        case .serious: return "\(cause) Frame rate may drop."
        case .critical: return "\(cause) Recording may stop."
        case .shutdown: return "Camera stopped to protect the phone."
        }
    }

    /// Pressure, then the microphone, then the transient notice. Storage is shown only by the remaining slot.
    static func bottomNotice(access: CaptureAccess, pressure: String?, notice: String?) -> String? {
        if let pressure { return pressure }
        if isMicrophoneOff(access) { return microphoneOff }
        return notice
    }

    static func isMicrophoneOff(_ access: CaptureAccess) -> Bool {
        access.microphone == .denied || access.microphone == .restricted
    }

    static func remaining(minutes: Int) -> RemainingTime {
        RemainingTime(text: minutes <= 0 ? storageFull : DataRateEstimator.durationText(minutes: minutes), isWarning: DataRateEstimator.isLowStorage(minutes: minutes))
    }

    static func canRecord(phase: CameraPhase, mode: CaptureMode, minutesRemaining: Int) -> Bool {
        guard phase == .ready else { return false }
        return mode == .photo || minutesRemaining > 0
    }
}
