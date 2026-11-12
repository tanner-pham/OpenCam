import SwiftUI

/// One adjustable readout as a button: tapping it opens its slider, switches to it, or closes it when it is the open one.
/// It reads only its own control, so a drag re-runs the readouts that show a value and not the bar around them. The hit
/// area is the readout's whole cell.
struct ControlReadout: View {
    let control: ManualControl
    let model: CameraModel
    var isCompact = false

    var body: some View {
        let state = model.readout(for: control)
        Button { model.toggleControl(control) } label: {
            ReadoutView(caption: control.caption, value: state.text, isCompact: isCompact, isSet: state.isSet, isOpen: state.isOpen)
                .opacity(state.isAvailable ? 1 : 0.4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!state.isAvailable)
        .accessibilityLabel(control.name)
        .accessibilityValue("\(state.spoken), \(state.isSet ? "set by hand" : "automatic")")
        .accessibilityHint(state.isOpen ? "Closes the slider." : "Opens the slider.")
        .accessibilityAddTraits(state.isOpen ? .isSelected : [])
    }
}
