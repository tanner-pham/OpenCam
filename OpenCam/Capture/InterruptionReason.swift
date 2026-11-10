import Foundation

nonisolated enum InterruptionReason: Sendable, Equatable {
    case background, cameraInUse, multipleForegroundApps, systemPressure, microphoneInUse, other

    /// Maps the raw value of `AVCaptureSession.InterruptionReason` (`AVCaptureSession.h`):
    /// 1 background, 2 audio device in use, 3 video device in use, 4 multiple foreground apps, 5 system pressure.
    init(avReason rawValue: Int) {
        switch rawValue {
        case 1: self = .background
        case 2: self = .microphoneInUse
        case 3: self = .cameraInUse
        case 4: self = .multipleForegroundApps
        case 5: self = .systemPressure
        default: self = .other
        }
    }

    var notice: String? {
        switch self {
        case .background: nil
        case .cameraInUse: "Camera paused. Another app is using it."
        case .multipleForegroundApps: "Camera paused while another app is on screen."
        case .systemPressure: "Camera paused to protect the phone."
        case .microphoneInUse: "Microphone in use by another app."
        case .other: "Camera paused."
        }
    }
}
