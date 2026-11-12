import Foundation

extension CameraModel {
    /// Today's sequence from `start(session:)`, lens discovery through the armed confirmation, over the protocol.
    /// False, with the failed phase set and no camera running, when the camera cannot start.
    func startCamera(on configurator: any SessionConfigurator, savedStart: Task<SessionConfiguration?, Never>?) async -> Bool {
        let lenses = await Self.discoverLenses(with: capabilitySource)
        launchTimeline.mark("lenses")
        guard !lenses.isEmpty else {
            Self.logger.error("[CameraModel:start] No camera found — {lenses: 0}")
            phase = .failed("The camera could not start.")
            return false
        }
        await loadCapabilities(lenses: lenses)
        if case .failed = phase { return false }
        launchTimeline.mark("capabilities")
        guard let configuration = sessionConfiguration else {
            Self.logger.error("[CameraModel:start] No lens selected — {lenses: \(lenses.count)}")
            phase = .failed("The camera could not start.")
            return false
        }
        let selection = currentSelection
        // Read before the configure and start, so an error handled while they are awaited is not lost.
        let errors = runtimeErrorCount
        do {
            try await configurator.configure(configuration)
        } catch {
            Self.logger.error("\(error.description, privacy: .public)")
            ErrorJournal.record(error.description)
            phase = .failed(Self.formatSetupFailed)
            return false
        }
        launchTimeline.mark("configured")
        // The look renderer's Metal device and CIContext are made now, off the main actor and at low priority, while the
        // session starts on its own queue: a look's frame view, which reads the renderer on the main actor, can exist only
        // once the phase is ready below, after the start has returned. Not awaited, so it never delays the first frame.
        Task(priority: .utility) { await LookRenderer.warmUp() }
        attachSession(configurator, configuredWith: configuration, selection: selection)
        await configurator.start()
        launchTimeline.mark("running")
        ErrorJournal.record(launchTimeline.line)
        isResettingMediaServices = false
        watchFrames(for: configuration)
        phase = .ready
        // Timed only once the start has returned, so a slow start never drops it, and for whatever the session last applied:
        // a selection changed during the first configure was applied by the chain before the phase was ready, so it armed
        // nothing itself. One the chain has still to apply arms its own once it has.
        if let lastWorking { confirmWhenRunning(lastWorking.configuration, since: errors) }
        releaseIfLibraryOpen()
        return true
    }

    /// The discovery sessions are created off the main actor.
    @concurrent nonisolated private static func discoverLenses(with source: CapabilitySource) async -> [Lens] {
        source.discoverLenses()
    }
}
