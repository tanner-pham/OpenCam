import SwiftUI

/// The open control's Auto, slider and close in a glass capsule, for where the strip is not used. The same three views serve
/// the strip. This view alone reads which control is open, so opening and closing re-run it and nothing larger; it draws
/// nothing while no control is open.
struct PictureSliderColumn: View {
    let model: CameraModel

    var body: some View {
        if let control = model.openControl {
            GlassEffectContainer(spacing: Theme.Space.s) {
                VStack(spacing: Theme.Space.s) {
                    // Top to bottom as in the portrait strip: slider, Auto, close.
                    ControlSlider(model: model)
                        .padding(.vertical, Theme.Space.xs)
                    if control.hasAutomatic { ControlAutoButton(model: model) }
                    ControlCloseButton(model: model)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .padding(Theme.Space.s)
                .glassEffect(.regular, in: .capsule)
            }
        }
    }
}
