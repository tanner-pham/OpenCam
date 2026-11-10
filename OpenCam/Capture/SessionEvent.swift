import Foundation

nonisolated enum SessionEvent: Sendable, Equatable {
    case interrupted(InterruptionReason)
    case interruptionEnded
    /// Carries a log message only; it never reaches the screen.
    case runtimeError(String)
    case pressure(PressureLevel, isThermal: Bool)
}
