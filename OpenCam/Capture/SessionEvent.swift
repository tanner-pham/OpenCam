import Foundation

nonisolated enum SessionEvent: Sendable, Equatable {
    case interrupted(InterruptionReason)
    case interruptionEnded
    /// Carries a log message only; it never reaches the screen.
    case runtimeError(String)
    /// The session runs again after a media-services reset.
    case restarted
    /// The microphone could not attach; video continues without sound. Carries a log message only.
    case microphoneUnavailable(String)
    case pressure(PressureLevel, isThermal: Bool)
    /// The data output that draws the look could not be added; the viewfinder keeps the preview layer.
    case framesUnavailable
    /// Everything before this in the stream belongs to a saved start that was released; the model ignores it.
    case savedStartReleased
}
