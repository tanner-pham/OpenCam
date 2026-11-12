import SwiftUI

struct ChipButton: View {
    let chip: Chip
    let isSelected: Bool
    var isSingleLine = false
    let action: () -> Void

    var body: some View {
        let button = Button(action: action) {
            VStack(spacing: 0) {
                Text(chip.title).font(.footnote.weight(.semibold)).lineLimit(isSingleLine ? 1 : nil)
                if let detail = chip.detail {
                    Text(detail).font(.caption2).monospacedDigit().foregroundStyle(isSelected ? .black.opacity(0.7) : .secondary)
                }
                if let estimate = chip.estimate {
                    ForEach([estimate.rate, estimate.time], id: \.self) { line in
                        Text(line).font(.caption2).monospacedDigit().lineLimit(1).fixedSize()
                            .foregroundStyle(isSelected ? .black.opacity(0.7) : .secondary)
                    }
                }
            }
            .foregroundStyle(isSelected ? .black : .primary)
            .opacity(chip.isAvailable ? 1 : 0.35)
            .frame(maxWidth: .infinity, minHeight: Theme.Size.chipLabelHeight)
        }
        .controlSize(.small)
        .disabled(!chip.isAvailable)
        .accessibilityLabel([chip.title, chip.estimate?.spoken ?? chip.detail].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(isSelected ? .isSelected : [])

        if isSelected {
            button.buttonStyle(.glassProminent).tint(Theme.accent)
        } else {
            button.buttonStyle(.glass)
        }
    }
}
