import SwiftUI
import UIKit

/// A transparent layer over the fitted picture that turns a finger or Apple Pencil into brush samples, in picture coordinates.
/// It takes every touch on the picture; one touch is followed at a time and any other is ignored.
struct BrushCanvas: UIViewRepresentable {
    let onBegin: (MaskPoint, Double?) -> Void
    let onMove: (MaskPoint, Double?) -> Void
    let onEnd: () -> Void

    func makeUIView(context: Context) -> BrushTouchView {
        let view = BrushTouchView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = false
        view.accessibilityLabel = "Brush canvas"
        return view
    }

    func updateUIView(_ view: BrushTouchView, context: Context) {
        view.onBegin = onBegin
        view.onMove = onMove
        view.onEnd = onEnd
    }
}

final class BrushTouchView: UIView {
    var onBegin: (MaskPoint, Double?) -> Void = { _, _ in }
    var onMove: (MaskPoint, Double?) -> Void = { _, _ in }
    var onEnd: () -> Void = {}

    private var activeTouch: UITouch?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard activeTouch == nil, let touch = touches.first else { return }
        activeTouch = touch
        onBegin(point(of: touch), Self.pressure(of: touch))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        // Every sample the screen took since the last call, not only the last, so a quick stroke stays smooth.
        for sample in event?.coalescedTouches(for: touch) ?? [touch] { onMove(point(of: sample), Self.pressure(of: sample)) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        onMove(point(of: touch), Self.pressure(of: touch))
        finish()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        finish()
    }

    private func finish() {
        activeTouch = nil
        onEnd()
    }

    private func point(of touch: UITouch) -> MaskPoint {
        MaskGeometry.point(touch.preciseLocation(in: self), in: bounds.size)
    }

    /// The Pencil's force as 0...1; nil for a finger, which has no pressure to scale by.
    private static func pressure(of touch: UITouch) -> Double? {
        guard touch.type == .pencil, touch.maximumPossibleForce > 0 else { return nil }
        return Double(touch.force / touch.maximumPossibleForce)
    }
}
