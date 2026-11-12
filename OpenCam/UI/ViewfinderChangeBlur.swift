import SwiftUI

extension EnvironmentValues {
    /// True while a camera change pauses the picture; the viewfinder blurs meanwhile.
    @Entry var isViewfinderChanging = false
}

/// Blurs the picture while the camera changes, as Apple's Camera does, so a paused picture does not read as a hang. It alone
/// reads the flag, so a change re-runs this small view and not the viewfinder. The opacity is derived from the flag, never held
/// in state, so a layout that appears mid-change (the mode switch swaps layouts) starts already blurred. Drawn over the picture
/// only; it never takes a touch. With Reduce Motion on it still shows: it is a cross-fade, not movement.
struct ViewfinderChangeBlur: View {
    @Environment(\.isViewfinderChanging) private var isChanging

    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .opacity(isChanging ? 1 : 0)
            .animation(isChanging ? .easeOut(duration: ViewfinderChange.fadeIn.seconds) : .easeInOut(duration: ViewfinderChange.fadeOut.seconds),
                       value: isChanging)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private extension Duration {
    var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
