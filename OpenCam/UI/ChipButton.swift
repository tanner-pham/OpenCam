import SwiftUI

struct ChipButton: View {
    let chip: Chip
    let isSelected: Bool
    let action: () -> Void

    /// Every line of a chip stays on one line and shrinks to this before it would grow into its neighbour or wrap.
    private static let minimumScale: CGFloat = 0.75

    var body: some View {
        let button = Button(action: action) {
            VStack(spacing: 0) {
                Text(chip.title).font(.footnote.weight(.semibold)).lineLimit(1).minimumScaleFactor(Self.minimumScale)
                if let detail = chip.detail {
                    Text(detail).font(.caption2).monospacedDigit().lineLimit(1).minimumScaleFactor(Self.minimumScale).foregroundStyle(isSelected ? .black.opacity(0.7) : .secondary)
                }
                if let estimate = chip.estimate {
                    ForEach([estimate.rate, estimate.time], id: \.self) { line in
                        Text(line).font(.caption2).monospacedDigit().lineLimit(1).minimumScaleFactor(Self.minimumScale)
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
