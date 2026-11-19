import SwiftUI

/// Over the picture: a tap sets the focus and exposure point, a hold locks both, a pinch zooms within the lens. Draws nothing and takes no touch unless the
/// camera can be aimed. `topInset` keeps the lock capsule clear of a readout bar drawn over the top of the picture.
struct ViewfinderGestureLayer: View {
    let model: CameraModel
    var topInset: CGFloat = 0

    @State private var size = CGSize.zero

    var body: some View {
        if model.canAim {
            Color.clear
                .contentShape(.rect)
                .gesture(FocusTapRecognizer { model.focusTapped(at: $0, in: size) })
                .gesture(FocusHoldRecognizer { model.focusHeld(at: $0, in: size) })
                .gesture(ZoomPinchRecognizer(model: model))
                .overlay {
                    if let marker = model.focusTap.marker {
                        FocusMarkerView(marker: marker) { model.focusMarkerFaded(serial: $0) }
                    }
                }
                .overlay(alignment: .top) {
                    if let text = model.focusTap.lockText {
                        FocusLockCapsule(text: text).padding(.top, topInset)
                    }
                }
                .onGeometryChange(for: CGSize.self, of: \.size) { size = $0 }
                // The scripted launch lock waits for the layout to settle and follows it, so it holds at the picture's real centre.
                .task(id: size) {
                    try? await Task.sleep(for: .milliseconds(400))
                    model.holdFocusOnLaunchIfAsked(in: size)
                }
        }
    }
}
