import Foundation

/// Which outputs a configuration change takes off the session and which it puts on, decided from plain values. Every removal
/// comes before any addition, so the session is never asked to hold the old path's outputs (the movie output, the writer's
/// full-size data output, a look's frame output) beside the new path's: a `canAddOutput` that said no would fail the configure
/// after the model had already changed its state.
nonisolated struct SessionOutputPlan: Equatable, Sendable {
    let removals: [SessionOutput]
    let additions: [SessionOutput]

    /// What the configuration needs. The movie output is the system recorder's; the writer's two data outputs are the writer
    /// path's, the sound one only with a microphone attached. Look frames are drawn only on the system path: with the writer's
    /// full-size output that would be two video data outputs on one session, which nothing has measured.
    static func wanted(mode: CaptureMode, recorder: RecorderPath, needsFrames: Bool, hasMicrophone: Bool) -> Set<SessionOutput> {
        var outputs: Set<SessionOutput> = []
        if mode == .photo { outputs.insert(.photo) }
        if mode == .video {
            switch recorder {
            case .system: outputs.insert(.movie)
            case .writer:
                outputs.insert(.writerVideo)
                if hasMicrophone { outputs.insert(.writerSound) }
            }
        }
        if needsFrames, recorder == .system { outputs.insert(.lookFrames) }
        return outputs
    }

    static func make(attached: Set<SessionOutput>, wanted: Set<SessionOutput>) -> SessionOutputPlan {
        SessionOutputPlan(removals: SessionOutput.allCases.filter { attached.contains($0) && !wanted.contains($0) },
                          additions: SessionOutput.allCases.filter { wanted.contains($0) && !attached.contains($0) })
    }
}
