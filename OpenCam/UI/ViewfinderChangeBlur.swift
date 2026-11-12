import SwiftUI

extension EnvironmentValues {
    /// True while a camera change pauses the picture; the viewfinder blurs meanwhile.
    @Entry var isViewfinderChanging = false
}

/// Blurs the picture while the camera changes, as Apple's Camera does, so a paused picture does not read as a hang. It alone
/// reads the flag, so a change re-runs this small view and not the viewfinder. The blur is in the view tree only while the
/// flag is up, so nothing is drawn over the live picture between changes. Whether it shows is derived from the flag, never held
/// in state, so a layout that appears mid-change (the mode switch swaps layouts) starts already blurred. Drawn over the picture
/// only; it never takes a touch. With Reduce Motion on it still shows: it is a cross-fade, not movement.
struct ViewfinderChangeBlur: View {
    @Environment(\.isViewfinderChanging) private var isChanging

    var body: some View {
        ZStack {
            if isChanging {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .transition(.opacity)
            }
        }
        .animation(isChanging ? .easeOut(duration: ViewfinderChange.fadeIn / .seconds(1))
                              : .easeInOut(duration: ViewfinderChange.fadeOut / .seconds(1)),
                   value: isChanging)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
