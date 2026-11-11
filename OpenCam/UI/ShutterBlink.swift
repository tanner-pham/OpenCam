import SwiftUI

extension EnvironmentValues {
    /// The photos taken so far; the viewfinder blinks each time it changes.
    @Entry var shutterBlinks = 0
}

/// The viewfinder goes dark for about a tenth of a second and comes back: opacity 0 to 1 in 0.04 s, back to 0 in 0.12 s.
/// Drawn over the picture only, and never takes a touch.
struct ShutterBlink: View {
    let trigger: Int

    var body: some View {
        Color.black
            .keyframeAnimator(initialValue: 0.0, trigger: trigger) { content, opacity in
                content.opacity(opacity)
            } keyframes: { _ in
                LinearKeyframe(1.0, duration: 0.04)
                LinearKeyframe(0.0, duration: 0.12)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
