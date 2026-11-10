import Foundation

/// Which Looks tile is selected for an edit. An edit keeps only a copy of the look's name, so the choice is made by values:
/// a look is selected when the edit's adjustments match its own on every step; "None" only when the edit has no adjustments.
/// A hand-made edit selects nothing, and looks with identical values are selected together.
nonisolated enum LookSelection {
    /// `look` nil is "None".
    static func isSelected(_ look: Look?, for adjustments: Adjustments) -> Bool {
        adjustments.matches(look?.adjustments ?? Adjustments())
    }
}
