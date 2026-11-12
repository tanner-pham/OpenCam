import SwiftUI

/// The photo readouts: shutter, ISO, EV, white balance and focus in equal cells, full size. The folded vertical photo layout
/// draws it under the picture and `TopReadoutBar` draws it in the horizontal layouts' bar. Each is a `ControlReadout` that
/// reads its own value: they change several times a second, and only they re-run for it, not this row or the layout around it.
struct PhotoReadoutRow: View {
    /// Left to right.
    nonisolated static let controls: [ManualControl] = [.shutter, .iso, .bias, .temperature, .focus]

    let model: CameraModel

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Self.controls, id: \.self) { ControlReadout(control: $0, model: model) }
        }
    }
}
