/// A reason a step of the check could not be made, in the house format.
nonisolated struct RawSizeCheckFailure: Error, Sendable {
    let message: String
    /// `.refused` when the phone did not offer it, `.unsafe` when a precondition of a safe request did not hold.
    let outcome: RawSizeCheckOutcome
    /// What did not hold, without the context.
    let description: String

    init(_ function: String, _ description: String, context: String, outcome: RawSizeCheckOutcome = .unsafe) {
        message = "[RawSizeCheck:\(function)] \(description) — {\(context)}"
        self.outcome = outcome
        self.description = description
    }
}
