import Foundation

extension CameraModel {
    static let framesUnavailableNotice = "The look cannot be shown in the viewfinder with this format."

    /// The session attaches the look's data output only while the viewfinder can draw the look, and never during a sweep,
    /// which must test the formats as they are without a look.
    var needsFrames: Bool { cameraLook != nil && isLookOffered && !isLookViewfinderUnavailable && !isSweeping }

    /// The look's frames cannot be drawn with this format: the viewfinder returns to the plain preview, the data output is
    /// detached, and the look stays selected (photos still take it). The next lens, mode, format or look change tries again.
    func framesUnavailable() {
        isLookViewfinderUnavailable = true
        showLookNotice(Self.framesUnavailableNotice)
        enqueueConfigure()
    }

    /// Frames stop while the camera is interrupted or reset; when it runs again the watch starts over, so frames that never
    /// resume fall back with the notice instead of leaving the last frame frozen over the hidden preview.
    /// The watch is armed only once the configures already queued have finished, so a configuration still being applied is
    /// never timed; a configure that finishes meanwhile arms its own watch, which cancels this one.
    func rewatchFrames() {
        frameWatch?.cancel()
        frameWatch = Task {
            await waitForQueuedConfigures()
            guard !Task.isCancelled, let requestedConfiguration else { return }
            watchFrames(for: requestedConfiguration)
        }
    }

    /// After a configure that needs frames reaches a running session, waits `FrameWatch.timeout` for the first one; with
    /// none, and the look still on for this configuration, falls back to the plain preview. A configuration without frames
    /// only cancels the last watch.
    func watchFrames(for configuration: SessionConfiguration) {
        frameWatch?.cancel()
        frameWatch = nil
        guard configuration.needsFrames, !isSessionStoppedForRescan, let cameraSession else { return }
        let frames = cameraSession.previewSource.frames
        let start = frames.deliveredCount
        let clock = ContinuousClock()
        let began = clock.now
        frameWatch = Task {
            do {
                try await Task.sleep(for: FrameWatch.timeout)
            } catch {
                return
            }
            let delivered = frames.deliveredCount - start
            guard FrameWatch.isStalled(framesSinceConfigure: delivered, elapsed: clock.now - began) else { return }
            // Frames stop for reasons of their own while the camera is paused or handed to the Library; only a running,
            // uninterrupted camera still asking for this configuration has stalled.
            guard needsFrames, requestedConfiguration == configuration, phase == .ready, !isInterrupted, !isLibraryPresented,
                  !isCameraReleasedForLibrary else { return }
            Self.logger.error("[CameraModel:watchFrames] No frame arrived — {lens: \(configuration.lens.id, privacy: .public), mode: \(configuration.mode.rawValue, privacy: .public)}")
            framesUnavailable()
        }
    }
}
