import SwiftUI

/// The group picker and the chosen group: its sliders, the curve editor, or the looks.
struct EditorPanel: View {
    @Bindable var model: EditorModel

    /// The space between one slider and the next name row.
    static let rowGap = Theme.Space.m

    var body: some View {
        VStack(spacing: 0) {
            ScrollingPicker(title: "Group", selection: $model.group, options: EditorGroup.allCases, label: \.title)
            switch model.group {
            case .looks: LooksPanel(model: model)
            case .curve: CurvePanel(model: model)
            case .mix: MixPanel(model: model)
            case .light, .colour, .detail, .effects: sliders
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
