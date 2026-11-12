import SwiftUI

/// One adjustment: its name and value on a row, the system slider below. Double-tapping the name row resets it.
struct AdjustmentSlider: View {
    /// The name shown on the row ("Luminance" under a grading wheel) and the slider's accessibility label.
    private let name: String
    private let accessibilityName: String
    @Binding private var value: Double
    private let range: ClosedRange<Double>
    private let valueText: String
    private let snap: (Double) -> Double
    private let onReset: () -> Void

    /// A slider for an adjustment: its range, step and value text come from `key`. `title` replaces the name on the row only;
    /// the slider's accessibility label stays `key.title`.
    init(key: AdjustmentKey, value: Binding<Double>, title: String? = nil, onReset: @escaping () -> Void) {
        name = title ?? key.title
        accessibilityName = key.title
        _value = value
        range = key.range
        valueText = key.valueText(value.wrappedValue)
        snap = key.snapped
        self.onReset = onReset
    }

    /// A slider for a value that is not an adjustment, such as a mask's feather, drawn the same way. Whole steps.
    init(title: String, value: Binding<Double>, range: ClosedRange<Double>, valueText: String, onReset: @escaping () -> Void) {
        name = title
        accessibilityName = title
        _value = value
        self.range = range
        self.valueText = valueText
        snap = { $0.rounded() }
        self.onReset = onReset
    }

    /// The space between a name row and its slider.
    private static let nameGap = Theme.Space.s
    /// How far the reset target reaches above the name row: the gap between rows (`EditorPanel.rowGap`) and 2 pt of the
    /// previous slider's frame, which has about 3 pt below its thumb, so never its thumb or track.
    static let reachUp = Theme.Space.m + Theme.Space.xs / 2
    /// How far it reaches below: the gap to its own slider and 4 pt of that slider's frame, which has about 4.3 pt above its thumb.
    private static let reachDown = nameGap + Theme.Space.xs

    var body: some View {
        VStack(alignment: .leading, spacing: Self.nameGap) {
            nameRow
                // A target of 18 pt text plus the reach, 44 pt, that takes no layout height: the padding sets the tappable
                // shape and the negative padding gives the space back. Drawn above its own slider so the reach below wins there.
                .padding(.top, Self.reachUp)
                .padding(.bottom, Self.reachDown)
                .contentShape(.rect)
                .onTapGesture(count: 2, perform: onReset)
                .padding(.top, -Self.reachUp)
                .padding(.bottom, -Self.reachDown)
                .zIndex(1)
                .accessibilityHidden(true)
            // Zero is "no change": the fill grows from it, so an untouched centred slider shows no fill. The value snaps to
            // `key.step` in the binding, because a stepped Slider draws a tick mark per step under the track.
            Slider(value: steppedValue, in: range, neutralValue: 0) {
                Text(accessibilityName)
            }
            .accessibilityValue(valueText)
            .accessibilityAction(named: "Reset", onReset)
        }
    }

    private var nameRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(name)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(valueText)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
        .lineLimit(1)
    }

    private var steppedValue: Binding<Double> {
        Binding(get: { value }, set: { value = snap($0) })
    }
}
