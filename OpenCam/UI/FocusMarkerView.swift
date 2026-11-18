import SwiftUI

/// The square drawn where the picture was touched. It settles from a little larger; an unlocked one stays 2.5 s, then fades over
/// 0.5 s and reports it; a locked one stays. A new marker restarts all of it.
struct FocusMarkerView: View {
    static let side: CGFloat = 72

    let marker: FocusMarker
    let onFaded: (Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reducesMotion
    @State private var scale: CGFloat = 1
    @State private var opacity: Double = 1

    var body: some View {
        Rectangle()
            .stroke(Theme.accent, lineWidth: 1.5)
            .frame(width: Self.side, height: Self.side)
            .scaleEffect(scale)
            .opacity(opacity)
            .position(marker.viewPoint)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .task(id: marker) { await run() }
    }

    private func run() async {
        opacity = 1
        scale = reducesMotion ? 1 : 1.2
        withAnimation(.easeOut(duration: 0.2)) { scale = 1 }
        guard !marker.isLocked else { return }
        do {
            try await Task.sleep(for: .seconds(2.5))
            withAnimation(.easeOut(duration: 0.5)) { opacity = 0 }
            try await Task.sleep(for: .seconds(0.5))
        } catch {
            return
        }
        onFaded(marker.serial)
    }
}
