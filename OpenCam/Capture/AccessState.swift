import AVFoundation

nonisolated enum AccessState: Sendable, Equatable {
    case notDetermined, authorized, denied, restricted

    init(_ status: AVAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .authorized: self = .authorized
        case .restricted: self = .restricted
        case .denied: self = .denied
        @unknown default: self = .denied
        }
    }
}
