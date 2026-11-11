import SwiftUI

/// The folded vertical photo layout's live readouts, read in their own body: they change several times a second, and
/// only this row re-runs for them, not the layout around it.
struct PhotoReadoutRow: View {
    let model: CameraModel

    var body: some View {
        HStack(spacing: 0) {
            ReadoutView(caption: "SHUTTER", value: model.shutterText)
            ReadoutView(caption: "ISO", value: model.isoText)
            ReadoutView(caption: "EV", value: model.exposureBiasText)
            ReadoutView(caption: "WB", value: model.whiteBalanceText)
            ReadoutView(caption: "FOCUS", value: model.focusText)
        }
    }
}
