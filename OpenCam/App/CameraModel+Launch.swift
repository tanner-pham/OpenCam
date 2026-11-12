import Foundation

extension CameraModel {
    /// Today's sequence from `start(session:)`, lens discovery through the armed confirmation, over the protocol.
    /// False, with the failed phase set and no camera running, when the camera cannot start.
    ///
    /// With a `savedStart` the session is already starting (or running) the configuration it was begun with; until the join
    /// below the model is as it is without one. At the join the started configuration is adopted when it equals the resolved
    /// one as a whole, else the session is released and today's configure runs. Every return before the join first releases it.
    func startCamera(on configurator: any SessionConfigurator, savedStart: Task<SessionConfiguration?, Never>?) async -> Bool {
        var pending = savedStart
        func discard(_ reason: String) async {
            guard let task = pending else { return }
            pending = nil
            await discardSavedStart(task, on: configurator, reason: reason)
        }
        let lenses = await Self.discoverLenses(with: capabilitySource)
        launchTimeline.mark("lenses")
        guard !lenses.isEmpty else {
            await discard("no camera found")
            Self.logger.error("[CameraModel:start] No camera found — {lenses: 0}")
            phase = .failed("The camera could not start.")
            return false
        }
        // The scan sets each camera's format directly, so a camera the saved start holds is let go of before it.
        await loadCapabilities(lenses: lenses, beforeScan: { await discard("format scan") })
        if case .failed = phase {
            await discard("format scan")
            return false
        }
        launchTimeline.mark("capabilities")
        guard let configuration = sessionConfiguration else {
            await discard("no lens selected")
            Self.logger.error("[CameraModel:start] No lens selected — {lenses: \(lenses.count)}")
            phase = .failed("The camera could not start.")
            return false
        }
        let selection = currentSelection
        // Read before the configure and start, so an error handled while they are awaited is not lost.
        let errors = runtimeErrorCount
        var isAdopted = false
        if let task = pending {
            if await task.value == configuration {
                isAdopted = true
                pending = nil
            } else {
                // Never corrected on the running session: released, then configured as today.
                await discard("differs")
            }
        }
        if !isAdopted {
            do {
                try await configurator.configure(configuration)
            } catch {
                Self.logger.error("\(error.description, privacy: .public)")
                ErrorJournal.record(error.description)
                phase = .failed(Self.formatSetupFailed)
                return false
            }
        }
        launchTimeline.mark("configured")
        // The look renderer's Metal device and CIContext are made now, off the main actor and at low priority, while the
        // session starts on its own queue: a look's frame view, which reads the renderer on the main actor, can exist only
        // once the phase is ready below, after the start has returned. Not awaited, so it never delays the first frame.
        Task(priority: .utility) { await LookRenderer.warmUp() }
        attachSession(configurator, configuredWith: configuration, selection: selection)
        // On an adopted saved start the session already runs, and this returns at once.
        await configurator.start()
        launchTimeline.mark("running")
        if isAdopted { launchTimeline.note("saved start") }
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

    /// Waits for the saved start to finish, then stops the session and lets its camera go, so nothing runs behind what follows.
    /// A saved start that already failed wrote its own journal line; any other is journalled here, once.
    func discardSavedStart(_ savedStart: Task<SessionConfiguration?, Never>, on configurator: any SessionConfigurator, reason: String) async {
        let started = await savedStart.value
        // Its start may have queued events; the session marks where they end and the model skips up to the mark.
        isIgnoringEventsUntilSavedStartReleased = true
        await configurator.releaseSavedStart()
        guard let started else { return }
        let message = "[CameraModel:startCamera] Saved start released — {reason: \(reason), lens: \(started.lens.id), mode: \(started.mode.rawValue)}"
        Self.logger.info("\(message, privacy: .public)")
        ErrorJournal.record(message)
    }

    /// The discovery sessions are created off the main actor.
    @concurrent nonisolated private static func discoverLenses(with source: CapabilitySource) async -> [Lens] {
        source.discoverLenses()
    }
}
