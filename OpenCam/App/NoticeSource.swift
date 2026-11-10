import Foundation

/// What put the shown notice there, so each event clears only its own.
nonisolated enum NoticeSource: Sendable, Equatable {
    /// A photo result or recording outcome, or a capture that could not begin. Only a newer capture result replaces it.
    case capture
    /// A camera interruption; cleared when it ends or when the session restarts.
    case interruption
    /// A selection the session could not apply; cleared by the next configure that works.
    case configuration
    /// A format scan that failed or skipped cameras.
    case scan
    /// The Library could not be built at launch, so its item cannot open it.
    case library
}
