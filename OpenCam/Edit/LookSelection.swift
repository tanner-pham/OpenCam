import Foundation

/// Which Looks tile is selected for an edit; exactly one at most. An edit keeps only a copy of the look's name, so the choice
/// is made by values: the looks whose values match the edit's on every step are candidates. Of those, the one whose name is
/// the name the edit recorded when the look was applied is selected, or else the first in the list (looks with identical
/// values, such as a duplicate, would otherwise all show as selected). "None" is selected only when the edit has no
/// adjustments, and then no look is. A hand-made edit selects nothing.
nonisolated enum LookSelection {
    /// `look` nil is "None". `looks` is the list as the Looks group shows it; `lookName` is the name the edit recorded.
    static func isSelected(_ look: Look?, among looks: [Look], for adjustments: Adjustments, lookName: String?) -> Bool {
        guard let look else { return adjustments.matches(Adjustments()) }
        return selectedLook(among: looks, for: adjustments, lookName: lookName)?.id == look.id
    }

    /// The one selected look, or nil when "None" or nothing is selected.
    static func selectedLook(among looks: [Look], for adjustments: Adjustments, lookName: String?) -> Look? {
        guard !adjustments.matches(Adjustments()) else { return nil }
        let matching = looks.filter { adjustments.matches($0.adjustments) }
        return matching.first { $0.name == lookName } ?? matching.first
    }
}
