/// A setup step of the recorder check that cannot go on; the message names the step and says why.
nonisolated struct RecorderCheckFailure: Error, Sendable {
    let message: String
    /// True when the failure is the asset writer refusing the output settings (`canApply` was false).
    var isSettingsRejection = false
}
