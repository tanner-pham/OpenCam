import Foundation

nonisolated enum AudioDeviceError: Error, Equatable, Sendable {
    case inputMissing(uid: String)
    case pinRefused(reason: String)
    case monitorRefused(reason: String)

    var description: String {
        switch self {
        case .inputMissing(let uid): "[AudioDevice:pin] Microphone is not listed — {uid: \(uid)}"
        case .pinRefused(let reason): "[AudioDevice:pin] The session refused the microphone — {reason: \(reason)}"
        case .monitorRefused(let reason): "[AudioDevice:startMonitor] The monitor could not start — {reason: \(reason)}"
        }
    }
}
