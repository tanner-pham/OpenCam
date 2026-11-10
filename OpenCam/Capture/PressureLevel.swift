import Foundation

nonisolated enum PressureLevel: String, Sendable {
    case nominal, fair, serious, critical, shutdown
}
