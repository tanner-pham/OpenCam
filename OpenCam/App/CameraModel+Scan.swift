import Foundation

extension CameraModel {
    /// Uses the cached capabilities when they were written on this OS build and model and all their lenses are present
    /// (lenses a scan skipped stay out until `rescanCapabilities`); otherwise scans.
    func loadCapabilities(lenses: [Lens]) async {
        let cache = CapabilityCache(directory: capabilitySource.cacheDirectory)
        if let cached = cache.load(osBuild: DeviceIdentity.osBuild(), modelIdentifier: DeviceIdentity.modelIdentifier()),
           let adopted = cached.adopting(discovered: lenses) {
            replaceCapabilities(adopted)
            return
        }
        phase = .scanning
        guard let capabilities = await scanCapabilities(lenses: lenses) else {
            phase = .failed("The camera could not start.")
            return
        }
        adoptScan(capabilities, lenses: lenses)
    }

    /// Only with a running camera (so never while formats are read, in the Simulator, or after a failure or denial),
    /// and never while recording or during a sweep.
    var canRescanCapabilities: Bool { phase == .ready && !isRecording && !isSweeping }

    /// Clears the cache and reads every camera again, for a camera that could not be read before. The session is stopped
    /// and holds no camera meanwhile, because the scan sets each camera's format directly; the saved selections are
    /// restored afterwards.
    func rescanCapabilities() async {
        guard canRescanCapabilities else { return }
        do {
            try CapabilityCache(directory: capabilitySource.cacheDirectory).clear()
        } catch {
            Self.logger.error("\(error.description, privacy: .public)")
        }
        phase = .scanning
        // No configure may queue from here, and none already queued may still be running when the scanner touches the cameras.
        isScanningFormats = true
        await waitForQueuedConfigures()
        await waitForPhotoCaptures()
        // The scanner adds each camera to a session of its own, so the main session lets go of its camera first;
        // the configure below attaches it again.
        isSessionStoppedForRescan = true
        defer { isSessionStoppedForRescan = false }
        await configurator?.releaseCameras()
        let lenses = capabilitySource.discoverLenses()
        let capabilities = await scanCapabilities(lenses: lenses)
        // A rescan starts from `.ready`; a failure reported meanwhile stands.
        if phase == .scanning { phase = .ready }
        // The scan moved the cameras' formats, so the session is configured again even when the selection is unchanged.
        requestedConfiguration = nil
        if let capabilities {
            adoptScan(capabilities, lenses: lenses)
        } else {
            show(Self.rescanFailedNotice, from: .scan)
        }
        do throws(CameraSessionError) {
            try await applySelection()
        } catch {
            // The scan released the camera and the session restores nothing after a rescan, so no camera is attached.
            Self.logger.error("[CameraModel:rescanCapabilities] No camera attached after the rescan — {error: \(error.description, privacy: .public)}")
            phase = .failed("The camera could not start.")
            return
        }
        await configurator?.start()
        // The look's frames can only arrive once the session runs, so the watch starts here, not in the configure above.
        isSessionStoppedForRescan = false
        rewatchFrames()
    }

    static let rescanFailedNotice = "Camera formats could not be read."

    static func skippedCamerasNotice(count: Int) -> String? {
        switch count {
        case 0: nil
        case 1: "1 camera could not be read."
        default: "\(count) cameras could not be read."
        }
    }

    /// Nil when the scan failed or no camera reported a usable format; the reason is logged.
    private func scanCapabilities(lenses: [Lens]) async -> CaptureCapabilities? {
        isScanningFormats = true
        defer { isScanningFormats = false }
        let formats: [FormatDescriptor]
        do {
            formats = try await capabilitySource.scan(lenses)
        } catch {
            Self.logger.error("\(error.description, privacy: .public)")
            return nil
        }
        let capabilities = CapabilityMapper.capabilities(lenses: lenses, formats: formats,
                                                         osBuild: DeviceIdentity.osBuild(), modelIdentifier: DeviceIdentity.modelIdentifier())
        guard !capabilities.lenses.isEmpty else {
            Self.logger.error("[CameraModel:scanCapabilities] No camera reported a usable format — {lenses: \(lenses.count), formats: \(formats.count)}")
            return nil
        }
        return capabilities
    }

    /// Applies a finished scan, says how many cameras were skipped, saves it to the cache and leaves a copy
    /// in Documents for comparison with the probe report.
    private func adoptScan(_ capabilities: CaptureCapabilities, lenses: [Lens]) {
        replaceCapabilities(capabilities)
        // This scan worked, so an earlier scan's notice is stale.
        clearNotice(from: .scan)
        // Notices count cameras, and a skipped camera can carry two lenses (1x and 2x).
        let skipped = Set(lenses.filter { capabilities.skippedLensIDs.contains($0.id) }.map(\.deviceUniqueID))
        if let skippedNotice = Self.skippedCamerasNotice(count: skipped.count) {
            show(skippedNotice, from: .scan)
        }
        for directory in [capabilitySource.cacheDirectory, capabilitySource.documentsDirectory].compactMap({ $0 }) {
            do {
                try CapabilityCache(directory: directory).save(capabilities)
            } catch {
                Self.logger.error("\(error.description, privacy: .public)")
            }
        }
    }
}
