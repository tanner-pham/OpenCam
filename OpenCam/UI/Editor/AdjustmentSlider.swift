import SwiftUI

/// One adjustment: its name and value on a row, the system slider below. Double-tapping the name resets it.
struct AdjustmentSlider: View {
    let key: AdjustmentKey
    @Binding var value: Double
    let onReset: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(key.title)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                    .onTapGesture(count: 2, perform: onReset)
                Text(key.valueText(value))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
            .lineLimit(1)
            .accessibilityHidden(true)
            Slider(value: $value, in: key.range, step: key.step)
                .frame(minHeight: Theme.Size.minTarget)
                .accessibilityLabel(key.title)
                .accessibilityValue(key.valueText(value))
                .accessibilityAction(named: "Reset", onReset)
        }
    }
}
