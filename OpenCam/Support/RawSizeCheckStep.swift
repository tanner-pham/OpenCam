/// One camera's share of the run, in the order the run does them: routes A, D and B on every camera first, then route C camera by
/// camera, so the long route C of one camera cannot use up the time the other cameras need for the short routes.
nonisolated struct RawSizeCheckStep: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        /// Routes A, D and B, on the photo preset.
        case photoPreset
        /// Route C: formats chosen by hand, with ProRAW where the format offers it.
        case chosenFormats
    }

    let phase: Phase
    let cameraIndex: Int

    static func plan(cameraCount: Int) -> [RawSizeCheckStep] {
        let indices = Array(0..<max(cameraCount, 0))
        return indices.map { RawSizeCheckStep(phase: .photoPreset, cameraIndex: $0) }
            + indices.map { RawSizeCheckStep(phase: .chosenFormats, cameraIndex: $0) }
    }
}
