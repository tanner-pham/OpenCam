import SwiftUI

/// Folded and vertical, photo. 3:4 picture, a readout row, then the shutter row.
struct FoldedVerticalView: View {
    let model: CaptureModel
    let size: CGSize

    private let photoReadouts: [Readout] = [.shutter, .iso, .ev, .wb]

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                ViewfinderStandIn(isFlat: false)
                if let readout = model.selectedReadout {
                    AdjustRulerView(readout: readout, model: model)
                }
            }
            .frame(width: size.width, height: size.width * 4 / 3)
            .clipped()

            VStack(spacing: Theme.Space.s) {
                HStack(spacing: 0) {
                    ForEach(photoReadouts) { readout in
                        ReadoutButton(caption: readout.caption, value: model.value(of: readout),
                                      isSelected: model.selectedReadout == readout) {
                            model.toggleSelection(readout)
                        }
                    }
                }
                HStack {
                    FormatButton(parts: model.summaryParts, isStacked: true) { model.sheet = .record }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    CaptureButton(symbol: "circle.inset.filled", tint: .white, symbolColor: .black, label: "Take photo") {}
                    HistogramView()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(.horizontal, Theme.Space.l)
            }
            .padding(.top, Theme.Space.s)
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }
}
