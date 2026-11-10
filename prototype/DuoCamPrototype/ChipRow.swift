import SwiftUI

/// A titled grid of equal-width glass chips. The selected chip is prominent; ruled-out chips are dimmed and
/// disabled, and one line under the grid says why.
struct ChipRow: View {
    let title: String
    let chips: [Chip]
    let selectedID: String
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
            if let reason = chips.first(where: { !$0.isAvailable })?.reason {
                Text(reason)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ChipButton: View {
    let chip: Chip
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        let button = Button(action: action) {
            VStack(spacing: 0) {
                Text(chip.id).font(.footnote.weight(.semibold))
                if let detail = chip.detail {
                    Text(detail).font(.caption2).monospacedDigit().foregroundStyle(isSelected ? .black.opacity(0.7) : .secondary)
                }
            }
            .foregroundStyle(isSelected ? .black : .primary)
            .opacity(chip.isAvailable ? 1 : 0.35)
            .frame(maxWidth: .infinity, minHeight: Theme.Size.chipLabelHeight)
        }
        .controlSize(.small)
        .disabled(!chip.isAvailable)
        .accessibilityAddTraits(isSelected ? .isSelected : [])

        if isSelected {
            button.buttonStyle(.glassProminent).tint(Theme.accent)
        } else {
            button.buttonStyle(.glass)
        }
    }
}
