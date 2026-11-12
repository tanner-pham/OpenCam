import SwiftUI

/// The open control's slider. It reads only `openSlider`, so a drag re-runs this view and not the screen.
struct ControlSlider: View {
    let model: CameraModel

    /// Where the fill starts: EV's zero, which is mid-scale; the bottom for every other control.
    static func originStep(for control: ManualControl, scale: ManualScale) -> Int {
        control == .bias ? scale.step(nearest: 0) : 0
    }

    var body: some View {
        if let slider = model.openSlider {
            StepSlider(
                stepCount: slider.stepCount,
                step: slider.step,
                adjustStride: slider.adjustStride,
                isAutomatic: slider.isAutomatic,
                label: slider.control.name,
                valueText: slider.spoken,
                originStep: model.scale(for: slider.control).map { Self.originStep(for: slider.control, scale: $0) } ?? 0,
                onChange: { model.setControl(slider.control, step: $0) }
            )
        }
    }
}
