import Foundation

/// A session that stops with a runtime error goes back to a selection that works, or says the camera stopped while Mode,
/// Lens, Record settings and Try again still work. One runtime error leads to at most one automatic recovery; a configuration
/// counts as confirmed once it has run for `runningConfirmation` with no runtime error.
extension CameraModel {
    static let cameraStopped = "The camera stopped."
    /// How long a configuration must run without a runtime error before it counts as confirmed.
    static let runningConfirmation: Duration = .milliseconds(1500)

    /// True in the stopped state: `phase == .failed(cameraStopped)` with a session attached, and no media-services reset in
    /// progress (the reset's own `.restarted` decides the phase).
    var isCameraStopped: Bool { phase == .failed(Self.cameraStopped) && configurator != nil && !isResettingMediaServices }

    /// The Library (released), a rescan or a sweep holds the session; each configures and starts it again when it ends,
    /// so nothing here starts it meanwhile.
    private var isSessionHeld: Bool {
        isCameraReleasedForLibrary || isScanningFormats || isSessionStoppedForRescan || isSweeping
    }

    /// The session restarts itself after a media-services reset (`CameraSession.restartAfterMediaServicesReset`, then
    /// `.restarted`), so a reset never reaches `cameraStopped`. The event carries text only, in `RuntimeErrorText`'s format.
    static func isMediaServicesReset(_ message: String) -> Bool {
        RuntimeErrorText.isMediaServicesReset(message)
    }

    /// Called for every runtime error that is not a media-services reset.
    func cameraStopped(_ message: String) {
        Self.logger.error("\(message, privacy: .public)")
        runtimeErrorCount += 1
        confirmation?.cancel()
        confirmation = nil
        // A reset whose restart failed is over: its restart was the one recovery, so the camera is stopped (below).
        let wasResetting = isResettingMediaServices
        isResettingMediaServices = false
        // Released for the Library: the session is stopped on purpose, and the Library's return configures and starts it
        // again; that return is the one recovery.
        if phase == .released || isCameraReleasedForLibrary {
            isRecoveryUnconfirmed = true
            return
        }
        phase = .failed(Self.cameraStopped)
        guard !wasResetting else { return }
        // An automatic recovery already ran and is not confirmed: the stopped state.
        guard !isRecoveryUnconfirmed, configurator != nil else { return }
        // A rescan's own configure and start follow; they are the one recovery.
        if isScanningFormats || isSessionStoppedForRescan {
            isRecoveryUnconfirmed = true
            return
        }
        // The recording ends as it always has (its result, or the stop that finds none), and the sweep restores the user's
        // selection; the recovery runs after that.
        if isRecording || isSweeping {
            isRecoveryDeferred = true
            return
        }
        recover()
    }

    /// The stopped state's "Try again": configures the current selection again and starts the session.
    func retryCamera() {
        guard isCameraStopped else { return }
        // A user action: the automatic restart is given back.
        autoRestarted = nil
        requestedConfiguration = nil
        enqueueConfigure()
    }

    /// Runs a recovery held back by a recording or a sweep, once neither runs.
    func resumeDeferredRecovery() {
        guard isRecoveryDeferred, !isRecording, !isSweeping else { return }
        isRecoveryDeferred = false
        guard isCameraStopped, !isRecoveryUnconfirmed else { return }
        recover()
    }

    /// Starts the session when the camera is stopped and nothing holds the session. Returns whether it started.
    func startIfStopped(_ configurator: any SessionConfigurator) async -> Bool {
        guard isCameraStopped, !isSessionHeld else { return false }
        await configurator.start()
        isResettingMediaServices = false
        return true
    }

    /// Confirms `configuration` once it has run for `confirmationDelay` with no runtime error since `errors` (the count read
    /// before its configure and start, so an error handled while they were awaited is not lost), as the session's last applied
    /// configuration, outside a sweep (a sweep option is never the user's) and while nothing holds the session. A stopped
    /// camera that got there is ready again. It must also still be the requested configuration with no configure queued since
    /// it was armed (`configureGeneration`), so an older confirmation never confirms what the chain has moved past, such as a
    /// sweep option left in place by a failed restore.
    func confirmWhenRunning(_ configuration: SessionConfiguration, since errors: Int) {
        confirmation?.cancel()
        let generation = configureGeneration
        let delay = confirmationDelay
        confirmation = Task {
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard errors == runtimeErrorCount, generation == configureGeneration, requestedConfiguration == configuration,
                  let lastWorking, lastWorking.configuration == configuration, !isSessionHeld,
                  phase == .ready || isCameraStopped else { return }
            confirmed = lastWorking
            isRecoveryUnconfirmed = false
            guard isCameraStopped else { return }
            phase = .ready
            // The look's frames are timed only while ready.
            watchFrames(for: configuration)
            releaseIfLibraryOpen()
        }
    }

    /// The one automatic recovery, by the rules of the plan: back to the confirmed selection when another one stopped, to
    /// the default when nothing is confirmed yet, else the same configuration once more.
    private func recover() {
        isRecoveryUnconfirmed = true
        let running = lastWorking
        if let confirmed, running?.configuration != confirmed.configuration {
            // The same allowance as rule 5: once per configuration until a user action, so a confirmed configuration that
            // keeps coming back (a look's frame fallback, say) cannot loop. Without it the stopped state stands.
            guard confirmed.configuration != autoRestarted else { return }
            autoRestarted = confirmed.configuration
            show(Self.formatFailedNotice, from: .configuration)
            restore(confirmed)
            restart(confirmed.configuration)
        } else if confirmed == nil, let defaultSelection, defaultSelection != currentSelection {
            show(Self.formatFailedNotice, from: .configuration)
            select(defaultSelection)
            restart(sessionConfiguration)
        } else if let running, running.configuration != autoRestarted {
            // Once per configuration until a user action; a second stop of the same one is the stopped state.
            autoRestarted = running.configuration
            restart(running.configuration)
        }
    }

    /// Configures `configuration` behind any queued configure, even unchanged, then starts the session. A configure that
    /// throws leaves the stopped state. A newer selection or runtime error overtakes it.
    private func restart(_ configuration: SessionConfiguration?) {
        guard let configurator, let configuration else { return }
        requestedConfiguration = configuration
        configureGeneration += 1
        let generation = configureGeneration
        let errors = runtimeErrorCount
        let selection = currentSelection
        let previous = configureTask
        let task = Task { () -> CameraSessionError? in
            _ = await previous?.value
            await waitForPhotoCaptures()
            // A newer selection's own configure starts the stopped camera; a newer runtime error left the stopped state.
            guard generation == configureGeneration, errors == runtimeErrorCount else { return nil }
            do throws(CameraSessionError) {
                try await configurator.configure(configuration)
            } catch {
                Self.logger.error("[CameraModel:restart] The stopped camera could not be configured again — {lens: \(configuration.lens.id, privacy: .public), mode: \(configuration.mode.rawValue, privacy: .public), error: \(error.description, privacy: .public)}")
                phase = .failed(Self.cameraStopped)
                return error
            }
            lastWorking = (configuration, selection)
            guard errors == runtimeErrorCount else { return nil }
            if await startIfStopped(configurator) || phase == .ready {
                confirmWhenRunning(configuration, since: errors)
            }
            watchFrames(for: configuration)
            return nil
        }
        configureTask = task
    }
}
