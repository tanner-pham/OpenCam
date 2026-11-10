import SwiftUI

/// Folded and vertical, photo. 3:4 picture, a row of live read-only readouts, then the shutter row.
struct FoldedVerticalView: View {
    let model: CameraModel
    let size: CGSize
    /// The system bars' top and bottom insets the controls keep clear of; zero on the folded phone.
    var insets = EdgeInsets()

    var body: some View {
        VStack(spacing: 0) {
            // 3:4 across the full width when it fits (the folded phone); otherwise as large as the controls below leave
            // room for, still 3:4, so the shutter row always shows.
            ViewfinderArea(phase: model.phase)
                .aspectRatio(3 / 4, contentMode: .fit)
                .clipped()
                .frame(maxWidth: size.width)
                .layoutPriority(1)

            VStack(spacing: Theme.Space.s) {
                HStack(spacing: 0) {
                    ReadoutView(caption: "SHUTTER", value: model.shutterText)
                    ReadoutView(caption: "ISO", value: model.isoText)
                    ReadoutView(caption: "EV", value: model.exposureBiasText)
                    ReadoutView(caption: "WB", value: model.whiteBalanceText)
                    ReadoutView(caption: "FOCUS", value: model.focusText)
                }
                HStack {
                    FormatButton(parts: model.summaryParts, isStacked: true) { model.openRecordSettings() }
                        .disabled(!model.canOpenRecordSettings)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    CaptureButton(model: model)
                    Color.clear.frame(maxWidth: .infinity)
                }
                .padding(.horizontal, Theme.Space.l)
                // The glass button draws beyond its label; the row keeps room for all of it when the picture takes the rest.
                .frame(minHeight: Theme.Size.captureButton + Theme.Space.l)
                NoticeLine(model: model)
                    .frame(height: Theme.Size.noticeLine)
            }
            .padding(.top, Theme.Space.s)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(.top, insets.top)
        .padding(.bottom, insets.bottom)
    }
}
