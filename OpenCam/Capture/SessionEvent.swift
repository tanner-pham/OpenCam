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
    /// The writer refused the sound settings of this clip, which records without sound. The microphone is fine: access is not
    /// changed. Carries a log message only; the model shows its own notice.
    case soundNotRecorded(String)
    case pressure(PressureLevel, isThermal: Bool)
    /// The data output that draws the look could not be added; the viewfinder keeps the preview layer.
    case framesUnavailable
    /// Everything before this in the stream belongs to a saved start that was released; the model ignores it.
    case savedStartReleased
    /// The Camera Control's own sliders took the screen (`sessionControlsWillEnterFullscreenAppearance`); the app hides its own.
    case systemControlsFullscreen
    /// The writer recorder's running count of frames missing from the clip; `clip` is `CaptureStore.clipKey`. Writer path only.
    case framesDropped(clip: String, total: Int)
}
