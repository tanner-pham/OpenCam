import SwiftUI

/// The open control's slider. It reads only `openSlider`, so a drag re-runs this view and not the screen.
struct ControlSlider: View {
    let model: CameraModel

    var body: some View {
        if let slider = model.openSlider {
            StepSlider(
                stepCount: slider.stepCount,
                step: slider.step,
                adjustStride: slider.adjustStride,
                isAutomatic: slider.isAutomatic,
                label: slider.control.name,
                valueText: slider.spoken,
                onChange: { model.setControl(slider.control, step: $0) }
            )
        }
    }
}
