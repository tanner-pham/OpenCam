import Foundation

/// What the Looks group's name prompt was opened for. The prompt is presented with this value and hands it to its Save action.
nonisolated enum LookNaming: Sendable, Equatable, Identifiable {
    case new
    case rename(Look)

    var id: String {
        switch self {
        case .new: "new"
        case .rename(let look): "rename " + look.id.uuidString
        }
    }

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
