import Foundation

/// What the Looks group's name alert was opened for. The alert is presented with this value and hands it to its Save action.
nonisolated enum LookNaming: Sendable, Equatable {
    case new
    case rename(Look)

    var title: String {
        switch self {
        case .new: "Save as look"
        case .rename: "Rename look"
        }
    }

    /// The look being renamed; nil for a new look.
    var look: Look? {
        switch self {
        case .new: nil
        case .rename(let look): look
        }
    }
}
