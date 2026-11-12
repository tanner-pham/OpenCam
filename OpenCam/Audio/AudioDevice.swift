import Foundation

/// The only door to the audio hardware: the real one drives `AVAudioSession`, the Simulator's reports a fixed route.
nonisolated protocol AudioDevice: Sendable {
    var changes: AsyncStream<AudioChange> { get }
    func route() async -> AudioRoute
    /// Runs `plan.steps(from:)` against what it last applied. On a throw, what was applied so far stands.
    func apply(_ plan: AudioPlan) async throws(AudioDeviceError)
}
