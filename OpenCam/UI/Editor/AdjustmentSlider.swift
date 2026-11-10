import SwiftUI

/// One adjustment: its name and value on a row, the system slider below. Double-tapping the row resets it.
struct AdjustmentSlider: View {
    let key: AdjustmentKey
    @Binding var value: Double
    let onReset: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(key.title)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(key.valueText(value))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
            .lineLimit(1)
            // The whole row is the reset target, at least 44 pt tall; the text sits at its foot, just above the slider.
            .frame(minHeight: Theme.Size.minTarget, alignment: .bottom)
            .contentShape(.rect)
            .onTapGesture(count: 2, perform: onReset)
            .accessibilityHidden(true)
            // Zero is "no change": the fill grows from it, so an untouched centred slider shows no fill. The value snaps to
            // `key.step` in the binding, because a stepped Slider draws a tick mark per step under the track.
            Slider(value: steppedValue, in: key.range, neutralValue: 0) {
                Text(key.title)
            }
            .frame(minHeight: Theme.Size.minTarget)
            .accessibilityValue(key.valueText(value))
            .accessibilityAction(named: "Reset", onReset)
        }
    }

    private var steppedValue: Binding<Double> {
        Binding(get: { value }, set: { value = ($0 / key.step).rounded() * key.step })
    }
}
