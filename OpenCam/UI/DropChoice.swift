import Foundation

/// What Record settings needs to draw the "When frames drop" row and report a choice.
struct DropChoice {
    let chips: [Chip]
    let selectedID: String
    let reason: String
    let onSelect: (String) -> Void
}
