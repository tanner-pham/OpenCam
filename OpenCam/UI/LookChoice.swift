import Foundation

/// What Record settings needs to draw the Look row and report a choice.
struct LookChoice {
    let chips: [Chip]
    let selectedID: String
    let reason: String?
    /// True when the sheet opens scrolled to the Look row.
    let scrollsIntoView: Bool
    let onSelect: (String) -> Void
}
