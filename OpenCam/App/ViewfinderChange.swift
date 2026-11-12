import Foundation

/// Which camera changes pause the picture, and how long the blur that covers the pause takes. The timings are tuning knobs:
/// when the first new frame arrives is a property of the phone.
nonisolated enum ViewfinderChange {
    /// How long the blur takes to come in, and to go out.
    static let fadeIn: Duration = .milliseconds(120)
    static let fadeOut: Duration = .milliseconds(300)
    /// After the configure returns, before the blur starts to clear.
    static let settle: Duration = .milliseconds(150)
    /// How long a change takes in the Simulator, which has no session.
    static let simulated: Duration = .milliseconds(400)

    /// True when `next` pauses the picture: another mode, camera, format, sound or frame feed. Only a different zoom on the
    /// same camera does not. The first configure (`previous` nil) happens behind the scanning screen.
    static func pausesPicture(from previous: SessionConfiguration?, to next: SessionConfiguration) -> Bool {
        guard let previous else { return false }
        return previous.mode != next.mode
            || previous.lens.deviceUniqueID != next.lens.deviceUniqueID
            || previous.video != next.video
            || previous.photo != next.photo
            || previous.includesAudio != next.includesAudio
            || previous.needsFrames != next.needsFrames
    }
}
