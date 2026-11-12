import SwiftUI

/// FPS, shutter, timecode, ISO, white balance, tint. Lives in the letterbox bar above the picture.
/// Live values from the camera, `--` whenever it reports none. Shutter, ISO, WB and tint open their sliders; FPS and
/// timecode are read-only.
struct TopReadoutBar: View {
    let model: CameraModel
    var isCompact = false
    /// The side of the system's vertical bar. The bar keeps the screen's corner inset on the other side.
    var stripEdge: HorizontalEdge? = .leading

    var body: some View {
        HStack(spacing: 0) {
            ReadoutView(caption: "FPS", value: model.frameRateText, isCompact: isCompact)
            ControlReadout(control: .shutter, model: model, isCompact: isCompact)
            TimecodeReadout(model: model, isCompact: isCompact).frame(width: isCompact ? 96 : 136)
            ControlReadout(control: .iso, model: model, isCompact: isCompact)
            ControlReadout(control: .temperature, model: model, isCompact: isCompact)
            ControlReadout(control: .tint, model: model, isCompact: isCompact)
        }
        .padding(stripEdge == .trailing ? .trailing : .leading, isCompact ? 0 : Theme.Space.s)
        .padding(stripEdge == .trailing ? .leading : .trailing, isCompact ? 0 : Theme.Size.cornerInset)
    }
}
