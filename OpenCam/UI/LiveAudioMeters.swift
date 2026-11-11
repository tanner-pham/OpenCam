import SwiftUI

/// The audio meters, reading the model's levels in their own body: the levels change ten times a second, and only this
/// small view re-runs for them, not the bar around it.
struct LiveAudioMeters: View {
    let model: CameraModel
    var width: CGFloat? = Theme.Size.meterWidth

    var body: some View {
        AudioMetersView(levels: model.shownMeterLevels, width: width)
    }
}
