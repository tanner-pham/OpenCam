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
                    HStack(alignment: .top, spacing: WheelGeometry.columnGap) {
                        ColourWheel(region: .shadows, model: model, diameter: diameter)
                        ColourWheel(region: .highlights, model: model, diameter: diameter)
                    }
                    ForEach([AdjustmentKey.gradingBlending, .gradingBalance], id: \.self) { key in
                        AdjustmentSlider(key: key, value: $model.adjustments[key]) { model.reset(key) }
                    }
                }
                .padding(.horizontal, WheelGeometry.sideInset)
                .padding(.top, Theme.Space.m)
                .padding(.bottom, Theme.Space.l)
                // SwiftUI hands a touch to the view with a gesture under it or, failing that, to the nearest one within the
                // touch's radius (about 16 pt); a content shape without a gesture does not count. Without this, a drag in the
                // gap between the wheels or in the margins reached a disc's drag and never scrolled. A tap here does nothing and
                // fails as the finger moves, so the scroll view takes the drag.
                .background { Color.clear.contentShape(.rect).onTapGesture {} }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}
