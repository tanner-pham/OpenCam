import SwiftUI

/// FPS, shutter, timecode, ISO, white balance, tint. Lives in the letterbox bar above the picture.
/// Live values read `--` until the monitoring task feeds them.
struct TopReadoutBar: View {
    let model: CameraModel
    var isCompact = false

    var body: some View {
        HStack(spacing: 0) {
            ReadoutView(caption: "FPS", value: model.frameRateText, isCompact: isCompact)
            ReadoutView(caption: "SHUTTER", value: "--", isCompact: isCompact)
            TimecodeReadout(model: model, isCompact: isCompact).frame(width: isCompact ? 96 : 136)
            ReadoutView(caption: "ISO", value: "--", isCompact: isCompact)
            ReadoutView(caption: "WB", value: "--", isCompact: isCompact)
            ReadoutView(caption: "TINT", value: "--", isCompact: isCompact)
        }
        .padding(.leading, isCompact ? 0 : Theme.Space.s)
        .padding(.trailing, isCompact ? 0 : Theme.Size.cornerInset)
    }
}
