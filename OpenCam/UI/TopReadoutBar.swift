import SwiftUI

/// FPS, shutter, timecode, ISO, white balance, tint. Lives in the letterbox bar above the picture.
/// Live, read-only values from the camera; `--` whenever the camera reports none.
struct TopReadoutBar: View {
    let model: CameraModel
    var isCompact = false

    var body: some View {
        HStack(spacing: 0) {
            ReadoutView(caption: "FPS", value: model.frameRateText, isCompact: isCompact)
            ReadoutView(caption: "SHUTTER", value: model.shutterText, isCompact: isCompact)
            TimecodeReadout(model: model, isCompact: isCompact).frame(width: isCompact ? 96 : 136)
            ReadoutView(caption: "ISO", value: model.isoText, isCompact: isCompact)
            ReadoutView(caption: "WB", value: model.whiteBalanceText, isCompact: isCompact)
            ReadoutView(caption: "TINT", value: model.tintText, isCompact: isCompact)
        }
        .padding(.leading, isCompact ? 0 : Theme.Space.s)
        .padding(.trailing, isCompact ? 0 : Theme.Size.cornerInset)
    }
}
