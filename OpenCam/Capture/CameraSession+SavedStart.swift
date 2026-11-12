import AVFoundation

extension CameraSession {
    /// What is already decided, without asking: never prompts.
    nonisolated static func currentAccess() -> CaptureAccess {
        CaptureAccess(camera: AccessState(AVCaptureDevice.authorizationStatus(for: .video)),
                      microphone: AccessState(AVCaptureDevice.authorizationStatus(for: .audio)))
    }

    /// Configures and starts `configuration` on the session's queue, in a detached task at `.userInitiated`, so it never waits
    /// for the main actor. The value is `configuration` once the start has returned, or nil when the configure threw, which is
    /// journalled once. The model decides afterwards whether to keep what ran.
    nonisolated func startSaved(_ configuration: SessionConfiguration) -> Task<SessionConfiguration?, Never> {
        Task.detached(priority: .userInitiated) {
            do throws(CameraSessionError) {
                try await self.configure(configuration)
            } catch {
                let message = "[CameraSession:startSaved] Saved start not used — {lens: \(configuration.lens.id), mode: \(configuration.mode.rawValue), error: \(error.description)}"
                Self.logger.error("\(message, privacy: .public)")
                ErrorJournal.record(message)
                return nil
            }
            await self.start()
            return configuration
        }
    }
}
