import SwiftUI

/// The folded vertical photo layout's readouts. Each is a `ControlReadout` that reads its own value: they change several
/// times a second, and only they re-run for it, not this row or the layout around it.
struct PhotoReadoutRow: View {
    let model: CameraModel

    var body: some View {
        HStack(spacing: 0) {
            ControlReadout(control: .shutter, model: model)
            ControlReadout(control: .iso, model: model)
            ControlReadout(control: .bias, model: model)
            ControlReadout(control: .temperature, model: model)
            ControlReadout(control: .focus, model: model)
        }
    }
}
