import Foundation

extension CameraModel {
    static let libraryUnavailableNotice = "The library could not be opened."
    static let cameraCouldNotStart = "The camera could not start."

    /// The Library covers the camera, so it opens under the same rule as the strip's Lens and Mode items: never while
    /// recording, sweeping or scanning formats.
    var canOpenLibrary: Bool { canChangeLensOrMode }

    /// Presents the Library and lets the camera go while it covers the screen: a running sensor under a full-screen cover
    /// costs battery and heat for nothing. Nothing is in flight to interrupt, because the Library cannot open while
    /// recording, sweeping or scanning. Without a working session (the Simulator, a denial, a failure) only the cover opens.
    func openLibrary() {
        guard canOpenLibrary else { return }
        guard isLibraryAvailable else {
            show(Self.libraryUnavailableNotice, from: .library)
            return
        }
        // The Library covers the camera: the slider closes and the controls return to automatic.
        resetManual()
        isLibraryPresented = true
        releaseIfLibraryOpen()
    }

    /// While the Library is open, a working camera lets go: called when the Library opens, and by `start` once the session
    /// runs, because the Library can open before the camera is ready (the permission prompt, a `-screen library` launch).
    func releaseIfLibraryOpen() {
        guard isLibraryPresented, configurator != nil, phase == .ready || phase == .released else { return }
        phase = .released
        enqueueLibraryHandoff { await $0.releaseCameraForLibrary() }
    }

    /// The Library has closed: the camera takes its sensor back with the current selection and runs again, then the strip's
    /// thumbnail is read again (a capture deleted in the Library stops showing, an import counts). Returns when done.
    /// A failure to come back ends in `.failed` with the plain copy.
    func closeLibrary() async {
        await enqueueLibraryHandoff { await $0.returnCameraFromLibrary() }.value
    }

    /// An import finished, possibly after the Library closed and the last capture was read: read it again so an imported
    /// photo shows on the strip.
    func libraryImportFinished() {
        refreshLastCapture()
    }

    /// Steps run one after another, so an open and a close can never overlap on the session.
    @discardableResult
    private func enqueueLibraryHandoff(_ step: @escaping (CameraModel) async -> Void) -> Task<Void, Never> {
        let previous = libraryHandoff
        let task = Task {
            await previous?.value
            await step(self)
        }
        libraryHandoff = task
        return task
    }

    /// Releases once: a second open while already released does nothing.
    private func releaseCameraForLibrary() async {
        guard isLibraryPresented, !isCameraReleasedForLibrary, let configurator else { return }
        await waitForQueuedConfigures()
        await waitForPhotoCaptures()
        await configurator.releaseCameras()
        isCameraReleasedForLibrary = true
    }

    /// While the camera is released for the Library, only the Library's return configures it, once, after clearing
    /// `requestedConfiguration`; a look the Library changed meanwhile waits for that return.
    var isHeldForLibrary: Bool { isCameraReleasedForLibrary && requestedConfiguration != nil }

    private func returnCameraFromLibrary() async {
        // Opened again before this step ran: the camera stays released for that Library.
        guard !isLibraryPresented else { return }
        // Every look change happens under the Library, so the looks are read again on every path, before the selection is configured.
        reloadLooks()
        defer { refreshLastCapture() }
        guard isCameraReleasedForLibrary, let configurator else {
            // Closed before the release ran: the session never let go, so the camera is simply back.
            if phase == .released { phase = .ready }
            return
        }
        // The release moved nothing, but the session holds no camera, so the selection is configured again even unchanged.
        requestedConfiguration = nil
        // Read before the configure and start, so an error handled while they are awaited is not lost.
        let errors = runtimeErrorCount
        do throws(CameraSessionError) {
            try await applySelection()
        } catch {
            Self.logger.error("[CameraModel:returnCameraFromLibrary] No camera attached after the Library closed — {error: \(error.description, privacy: .public)}")
            // The failed state says it all; the session still holds no camera, so the next close of the Library retries.
            clearNotice(from: .configuration)
            phase = .failed(Self.cameraCouldNotStart)
            return
        }
        await configurator.start()
        isResettingMediaServices = false
        isCameraReleasedForLibrary = false
        // The session runs again; once it has run long enough it is confirmed, and a camera that stopped meanwhile is ready.
        if let lastWorking { confirmWhenRunning(lastWorking.configuration, since: errors) }
        // A selection changed while the camera started was held; it is configured now, and its own configure watches frames.
        if enqueueConfigure() == nil, let configuration = requestedConfiguration {
            watchFrames(for: configuration)
        }
        // A failure reported meanwhile stands, except this step's own earlier one, which the retry has just mended. A Library
        // opened meanwhile releases the camera again in a step of its own.
        guard phase == .released || phase == .failed(Self.cameraCouldNotStart) else { return }
        // A runtime error handled during this configure and start: the return was the one recovery, so the camera is stopped.
        guard errors == runtimeErrorCount else {
            phase = .failed(Self.cameraStopped)
            return
        }
        phase = .ready
        releaseIfLibraryOpen()
    }
}
