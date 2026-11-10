import SwiftUI

/// Folded and vertical, photo. 3:4 picture, a readout row, then the shutter row.
struct FoldedVerticalView: View {
    let model: CameraModel
    let size: CGSize

    var body: some View {
        VStack(spacing: 0) {
            ViewfinderArea(phase: model.phase)
                .frame(width: size.width, height: size.width * 4 / 3)
                .clipped()

            VStack(spacing: Theme.Space.s) {
                HStack(spacing: 0) {
                    ReadoutView(caption: "SHUTTER", value: "--")
                    ReadoutView(caption: "ISO", value: "--")
                    ReadoutView(caption: "EV", value: "--")
                    ReadoutView(caption: "WB", value: "--")
                }
                HStack {
                    FormatButton(parts: model.summaryParts, isStacked: true) { model.openRecordSettings() }
                        .disabled(!model.canOpenRecordSettings)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    CaptureButton(model: model)
                    Color.clear.frame(maxWidth: .infinity)
                }
                .padding(.horizontal, Theme.Space.l)
            }
            .padding(.top, Theme.Space.s)
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }
}
