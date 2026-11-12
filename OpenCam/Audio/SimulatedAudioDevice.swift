import Foundation

/// The Simulator's audio: a fixed route chosen by launch flags, and nothing applied. The Simulator has no microphone routing
/// worth driving, so the section is checked against these routes.
nonisolated struct SimulatedAudioDevice: AudioDevice {
    let changes: AsyncStream<AudioChange>
    private let hasWiredMicrophone: Bool
    private let hasHeadphones: Bool

    init(config: LaunchConfig) {
        hasWiredMicrophone = config.hasWiredMicrophone
        hasHeadphones = config.hasHeadphones
        changes = AsyncStream.makeStream(of: AudioChange.self).stream
    }

    func route() async -> AudioRoute {
        var inputs = [AudioInput(uid: "simulated.builtin", kind: .builtIn, name: "iPhone Microphone", dataSources: [
            AudioDataSource(id: 1, name: "Front", orientation: "Front"),
            AudioDataSource(id: 2, name: "Back", orientation: "Back"),
            AudioDataSource(id: 3, name: "Bottom", orientation: "Bottom")])]
        if hasWiredMicrophone {
            inputs.append(AudioInput(uid: "simulated.headset", kind: .wired, name: "Headset microphone", dataSources: []))
        }
        return AudioRoute(inputs: inputs, outputs: [hasHeadphones ? .wired : .builtIn])
    }

    func apply(_ plan: AudioPlan) async throws(AudioDeviceError) {}
}
