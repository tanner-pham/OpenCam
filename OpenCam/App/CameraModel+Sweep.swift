import Foundation

extension CameraModel: SweepDriver {
    /// The format sweep needs a working camera; the Simulator and every failed or denied state read this.
    static let sweepNeedsCamera = "The sweep needs the camera."

    /// Every video option of the current lens that a selection can reach, in the order the device reported them.
    var sweepOptions: [VideoOption] {
        let resolver = recordResolver
        return capabilities.videoOptions.filter { $0.lensID == lensID && resolver.option(for: Self.selection(from: $0)) == $0 }
    }

    /// Never while recording, while formats are read, or during another sweep; only in video mode with a working camera.
    var canStartSweep: Bool {
        phase == .ready && mode == .video && !isRecording && !isScanningFormats && !isSweeping && cameraSession != nil
            && canCapture && !sweepOptions.isEmpty
    }

    /// Red text in Record settings and the warning style on the format summary when the selection failed the last sweep.
    var sweepCaption: String? {
        mode == .video ? failedCombinations.caption(for: shownVideoOption) : nil
    }

    /// The format summary's long press, in video mode.
    func openSweep() {
        guard mode == .video, canOpenRecordSettings else { return }
        closeControl()
        sheet = .sweep
    }

    /// Sweeps the current lens one option at a time with the model as the sweep's driver.
    func startSweep() async {
        guard canStartSweep, let lens = currentLens,
              let store = store(failureNotice: RecordingOutcome.failedNotice) else { return }
        await runSweep(FormatSweep(driver: self, store: store, lens: lens, options: sweepOptions, keepsClips: keepsSweepClips),
                       lensID: lens.id)
    }

    /// Holds the controls while `sweep` runs, then puts the user's selection back (waiting at most the sweep's start
    /// deadline for it to apply), unlocks the controls whatever happened, and keeps the failed options for `lensID`.
    /// The user's saved selection is untouched throughout.
    func runSweep(_ sweep: FormatSweep, lensID: String) async {
        let userRecord = record
        self.sweep = sweep
        // The sweep drives its own formats: nothing set by hand carries into it.
        resetManual()
        isSweeping = true
        await sweep.run()
        record = userRecord
        let restore = BoundedWait<Bool>()
        let isRestored = await restore.run(limit: sweep.deadlines.start) { [weak self] in
            guard let self else { return false }
            do throws(CameraSessionError) {
                try await applySelection()
                return true
            } catch {
                // The session stays on the last option that worked, and the notice says the format could not be used.
                Self.logger.error("[CameraModel:runSweep] The user's selection could not be restored — {lens: \(lensID, privacy: .public), error: \(error.description, privacy: .public)}")
                return false
            }
        } ?? false
        if !isRestored {
            Self.logger.error("[CameraModel:runSweep] The user's selection was not applied — {lens: \(lensID, privacy: .public)}")
        }
        isSweeping = false
        // The look was suspended during the sweep: it is settled once against the restored selection, and one configure
        // brings the data output back if the look is still on.
        settleLook()
        enqueueConfigure()
        // A runtime error during the sweep stopped the camera; it recovers now from the restored selection.
        resumeDeferredRecovery()
        // A selection still queued behind a stuck configure or recording applies when that ends, and is the user's, so it is
        // saved; after a failed restore the selection is a sweep option, which never is.
        if record == userRecord { persist() }
        // Only rows with a real answer change the list; a row that timed out, or one never reached, keeps its earlier entry.
        let answered = sweep.rows.filter(\.hasAnswer)
        failedCombinations = failedCombinations.updating(lensID: lensID,
                                                         passed: answered.filter { $0.status == .pass }.map(\.requested),
                                                         failed: answered.filter { $0.status == .fail }.map(\.requested))
        do throws(CapabilityError) {
            try failedCombinations.save(directory: capabilitySource.cacheDirectory)
        } catch {
            Self.logger.error("\(error.description, privacy: .public)")
        }
    }

    func cancelSweep() {
        sweep?.cancel()
    }

    /// Marks `url` as a sweep clip; `startRecording` calls it for every clip it starts during a sweep.
    func recordSweepClip(_ url: URL) {
        sweepClips.insert(CaptureStore.clipKey(for: url))
    }

    // MARK: SweepDriver

    /// The session runs and is not interrupted (any reason, backgrounding included).
    var isCameraUsable: Bool { phase == .ready && !isInterrupted }

    /// A recording still running (one that passed its deadline) would hold the configure back, so the option fails at once.
    func applySweepOption(_ option: VideoOption) async throws(CameraSessionError) {
        guard !isRecording else { throw .recordingInProgress }
        record = Self.selection(from: option)
        try await applySelection()
    }

    func beginSweepClip() async -> Bool {
        guard let start = startRecording() else { return false }
        await start.value
        return true
    }

    func endSweepClip() {
        stopRecording()
    }

    private static func selection(from option: VideoOption) -> RecordSelection {
        RecordSelection(family: option.codec.family, quality: option.codec.quality, resolution: option.resolution,
                        frameRate: option.frameRate, colour: option.colour)
    }
}
