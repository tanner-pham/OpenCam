import SwiftUI

/// Folded and horizontal. A 16:9 picture fills the width; readouts live in the bars above and below it.
struct FoldedHorizontalView: View {
    let model: CaptureModel
    let size: CGSize

    var body: some View {
        VStack(spacing: 0) {
            TopReadoutBar(model: model)
                .frame(height: Theme.Size.topBar)
            ZStack(alignment: .bottom) {
                ViewfinderStandIn(isFlat: model.lut == .off)
                if let readout = model.selectedReadout {
                    AdjustRulerView(readout: readout, model: model)
                }
            }
            .frame(width: size.width, height: size.width * 9 / 16)
            .clipped()
            BottomBar(model: model)
                .frame(maxHeight: .infinity)
        }
    }
}
