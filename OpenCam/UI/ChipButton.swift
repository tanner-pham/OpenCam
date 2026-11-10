import SwiftUI

struct ChipButton: View {
    let chip: Chip
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        let button = Button(action: action) {
            VStack(spacing: 0) {
                Text(chip.title).font(.footnote.weight(.semibold))
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
