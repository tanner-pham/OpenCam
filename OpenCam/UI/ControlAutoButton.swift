import SwiftUI

/// Hands the open control back to the camera. Empty for a control with no automatic state (EV).
struct ControlAutoButton: View {
    let model: CameraModel

    var body: some View {
        if let slider = model.openSlider, slider.control.hasAutomatic {
            Button { model.setAutomatic(slider.control) } label: {
                Text("Auto")
                    .font(Theme.Text.compactValue)
                    .foregroundStyle(slider.isAutomatic ? Theme.accent : Color.primary)
                    .frame(minWidth: Theme.Size.minTarget, minHeight: Theme.Size.minTarget)
            }
            .accessibilityLabel("Auto")
            .accessibilityValue(slider.isAutomatic ? "On" : "Off")
            .accessibilityHint(Self.hint(for: slider.control))
            .accessibilityAddTraits(slider.isAutomatic ? .isSelected : [])
        }
    }

    private static func hint(for control: ManualControl) -> String {
        switch control.group {
        case .exposure: "Returns shutter and ISO to automatic."
        case .whiteBalance: "Returns white balance and tint to automatic."
        case .focus: "Returns focus to automatic."
        case .bias: ""
        }
    }
}
