import SwiftUI

/// The group picker and the chosen group: its sliders, or the looks.
struct EditorPanel: View {
    @Bindable var model: EditorModel

    /// The space between one slider and the next name row.
    static let rowGap = Theme.Space.m

    var body: some View {
        VStack(spacing: 0) {
            Picker("Group", selection: $model.group) {
                ForEach(EditorGroup.allCases, id: \.self) { group in
                    Text(group.title).tag(group)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, Theme.Space.l)
            if model.group == .looks {
                LooksPanel(model: model)
            } else {
                sliders
            }
        }
        .padding(.top, Theme.Space.xs)
    }

    private var sliders: some View {
        ScrollView {
            VStack(spacing: Self.rowGap) {
                ForEach(model.group.keys, id: \.self) { key in
                    AdjustmentSlider(key: key, value: $model.adjustments[key]) { model.reset(key) }
                }
            }
            .padding(.horizontal, Theme.Space.l)
            // The gap under the picker is inside the scroll view, as tall as the first row's reset reach, because the
            // scroll view stops touches at its edge.
            .padding(.top, AdjustmentSlider.reachUp)
            .padding(.bottom, Theme.Space.l)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}
