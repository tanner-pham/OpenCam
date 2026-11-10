import SwiftUI

/// A titled grid of equal-width glass chips. The selected chip is prominent; ruled-out chips are dimmed and
/// disabled, and one line under the grid says why.
struct ChipRow: View {
    let title: String
    let chips: [Chip]
    let selectedID: String
    let reason: String?
    let columns: Int
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            GlassEffectContainer(spacing: 0) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Space.s), count: columns),
                          spacing: Theme.Space.xs) {
                    ForEach(chips) { chip in
                        ChipButton(chip: chip, isSelected: chip.id == selectedID) { onSelect(chip.id) }
                    }
                }
            }
            if let reason {
                Text(reason)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
