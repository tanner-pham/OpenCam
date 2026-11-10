import SwiftUI

/// FPS, shutter, timecode, ISO, white balance, tint. Lives in the letterbox bar above the picture.
struct TopReadoutBar: View {
    let model: CaptureModel
    var isCompact = false

    var body: some View {
        HStack(spacing: 0) {
            readout(.fps)
            readout(.shutter)
            TimecodeReadout(model: model, isCompact: isCompact).frame(width: isCompact ? 96 : 136)
            readout(.iso)
            readout(.wb)
            readout(.tint)
        }
        .padding(.leading, isCompact ? 0 : Theme.Space.s)
        .padding(.trailing, isCompact ? 0 : Theme.Size.cornerInset)
    }

    private func readout(_ readout: Readout) -> some View {
        ReadoutButton(caption: readout.caption, value: model.value(of: readout),
                      isSelected: model.selectedReadout == readout, isCompact: isCompact) {
            model.toggleSelection(readout)
        }
    }
}
