import SwiftUI

/// The Grading group: a Shadows / Midtones / Highlights picker above the scroll view, then the chosen range's wheel, Blending
/// and Balance. One wheel at a time keeps the picker, the wheel and its luminance in the panel at rest. A drag that starts
/// beside the disc scrolls the panel; one that starts on it moves the puck.
struct GradingPanel: View {
    @Bindable var model: EditorModel

    var body: some View {
        VStack(spacing: 0) {
            Picker("Tonal range", selection: $model.gradingRegion) {
                ForEach(GradingRegion.allCases, id: \.self) { region in Text(region.title).tag(region) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.large)
            .frame(minHeight: Theme.Size.minTarget)
            .padding(.horizontal, WheelGeometry.sideInset)
            .padding(.top, Theme.Space.m)
            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: EditorPanel.rowGap) {
                        ColourWheel(region: model.gradingRegion, model: model, diameter: WheelGeometry.diameter(forWidth: geo.size.width))
                        ForEach([AdjustmentKey.gradingBlending, .gradingBalance], id: \.self) { key in
                            AdjustmentSlider(key: key, value: $model.adjustments[key]) { model.reset(key) }
                        }
                    }
                    .padding(.horizontal, WheelGeometry.sideInset)
                    .padding(.top, Theme.Space.m)
                    .padding(.bottom, Theme.Space.l)
                    // SwiftUI hands a touch to the view with a gesture under it or, failing that, to the nearest one within the
                    // touch's radius (about 16 pt); a content shape without a gesture does not count. Without this, a drag in the
                    // margins beside the disc reached the disc's drag and never scrolled. A tap here does nothing and fails as the
                    // finger moves, so the scroll view takes the drag.
                    .background { Color.clear.contentShape(.rect).onTapGesture {}.accessibilityHidden(true) }
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
    }
}
