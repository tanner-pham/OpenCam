/// A reason a step of the check could not be made, in the house format.
nonisolated struct RawSizeCheckFailure: Error, Sendable {
    let message: String

    init(_ function: String, _ description: String, context: String) {
        message = "[RawSizeCheck:\(function)] \(description) — {\(context)}"
    }
}
