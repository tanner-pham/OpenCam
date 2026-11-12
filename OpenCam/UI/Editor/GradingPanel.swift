import SwiftUI

/// The Grading group: the Midtones wheel centred on top, Shadows and Highlights side by side below it, then Blending and
/// Balance, in one scroll view. A drag that starts between the wheels scrolls the panel; one that starts on a disc moves its puck.
struct GradingPanel: View {
    @Bindable var model: EditorModel

    var body: some View {
        GeometryReader { geo in
            let diameter = WheelGeometry.diameter(forWidth: geo.size.width)
            ScrollView {
                VStack(spacing: EditorPanel.rowGap) {
                    ColourWheel(region: .midtones, model: model, diameter: diameter)
                    HStack(alignment: .top, spacing: Theme.Space.m) {
                        ColourWheel(region: .shadows, model: model, diameter: diameter)
                        ColourWheel(region: .highlights, model: model, diameter: diameter)
                    }
                    ForEach([AdjustmentKey.gradingBlending, .gradingBalance], id: \.self) { key in
                        AdjustmentSlider(key: key, value: $model.adjustments[key]) { model.reset(key) }
                    }
                }
                .padding(.horizontal, Theme.Space.l)
                .padding(.top, Theme.Space.m)
                .padding(.bottom, Theme.Space.l)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}
