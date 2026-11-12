import SwiftUI

/// The readouts in the bar above the picture. Video: FPS, shutter, timecode, ISO, white balance, tint. Photo: the photo row's
/// shutter, ISO, EV, white balance and focus, with no FPS and no timecode. Live values from the camera, `--` whenever it
/// reports none. Every `ControlReadout` opens its slider; FPS and timecode are read-only.
struct TopReadoutBar: View {
    /// One cell of the bar.
    nonisolated enum Readout: Equatable {
        case frameRate, timecode
        case control(ManualControl)
    }

    /// The cells for `mode`, left to right.
    nonisolated static func readouts(for mode: CaptureMode) -> [Readout] {
        switch mode {
        case .video: [.frameRate, .control(.shutter), .timecode, .control(.iso), .control(.temperature), .control(.tint)]
        case .photo: PhotoReadoutRow.controls.map { .control($0) }
        }
    }

    let model: CameraModel
    var isCompact = false
    /// The side of the system's vertical bar. The bar keeps the screen's corner inset on the other side.
    var stripEdge: HorizontalEdge? = .leading

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(Self.readouts(for: model.mode).enumerated()), id: \.offset) { cell($0.element) }
        }
        .padding(stripEdge == .trailing ? .trailing : .leading, isCompact ? 0 : Theme.Space.s)
        .padding(stripEdge == .trailing ? .leading : .trailing, isCompact ? 0 : Theme.Size.cornerInset)
    }

    @ViewBuilder private func cell(_ readout: Readout) -> some View {
        switch readout {
        case .frameRate: ReadoutView(caption: "FPS", value: model.frameRateText, isCompact: isCompact)
        case .timecode: TimecodeReadout(model: model, isCompact: isCompact).frame(width: isCompact ? 96 : 136)
        case .control(let control): ControlReadout(control: control, model: model, isCompact: isCompact)
        }
    }
}
