import SwiftUI

/// A vertical slider over a fixed number of steps, `Theme.Size.minTarget` wide. It owns its drag: the thumb moves by the
/// distance dragged from where it was, so a touch alone changes nothing. Step 0 is the bottom; up is more. It draws track,
/// fill and thumb only: the strip's pill or the picture's column supplies the glass.
///
/// With no step (the camera reports no value) the thumb sits at the bottom, dimmed, and a drag from there works as from step 0.
struct StepSlider: View {
    let stepCount: Int
    let step: Int?
    let adjustStride: Int
    /// The thumb follows the live value and is drawn dimmed.
    let isAutomatic: Bool
    let label: String
    let valueText: String
    /// The step the fill starts from: 0 (the bottom) except where the scale has a natural zero in the middle, as EV does.
    var originStep = 0
    var length = Theme.Size.sliderLength
    let onChange: (Int) -> Void

    /// The step the current drag started from; nil between drags.
    @State private var dragStart: Int?
    /// The step this drag last sent; nil until it sends one.
    @State private var lastSent: Int?

    private let trackWidth: CGFloat = 6

    /// Where the thumb's centre can travel.
    private var travel: CGFloat { max(length - Theme.Size.sliderThumb, 0) }

    private var shownStep: Int { Self.clamped(step ?? 0, stepCount: stepCount) }

    private var fraction: CGFloat {
        stepCount > 1 ? CGFloat(shownStep) / CGFloat(stepCount - 1) : 0
    }

    /// The step after dragging `translation` points (SwiftUI's y, so up is negative) from `start`, over `travel` points of
    /// thumb travel, clamped to the scale. Pure; one step or no travel never divides by zero.
    nonisolated static func step(from start: Int, translation: CGFloat, travel: CGFloat, stepCount: Int) -> Int {
        let start = clamped(start, stepCount: stepCount)
        guard stepCount > 1, travel > 0, translation.isFinite else { return start }
        let moved = (-translation / travel * CGFloat(stepCount - 1)).rounded()
        guard abs(moved) < CGFloat(stepCount) else { return moved > 0 ? stepCount - 1 : 0 }
        return clamped(start + Int(moved), stepCount: stepCount)
    }

    /// Whether a drag now at `next` sends it: only when it differs from the last step this drag sent, or from the step it
    /// started on when it has sent none. So a touch alone sends nothing, and dragging back to the start step sends it.
    nonisolated static func sends(_ next: Int, start: Int, lastSent: Int?) -> Bool {
        next != (lastSent ?? start)
    }

    /// The accent fill's span, from `bottom` points above the track's bottom, `height` tall: from the origin step to the thumb. From
    /// step 0 it is the track's bottom to the thumb's centre; from any other origin (EV's zero) it runs between the two centres,
    /// and is empty while the thumb is on the origin. Pure.
    nonisolated static func fill(originStep: Int, step: Int, stepCount: Int, length: CGFloat, thumb: CGFloat) -> (bottom: CGFloat, height: CGFloat) {
        let travel = max(length - thumb, 0)
        func centre(_ step: Int) -> CGFloat {
            guard stepCount > 1 else { return thumb / 2 }
            return thumb / 2 + travel * CGFloat(clamped(step, stepCount: stepCount)) / CGFloat(stepCount - 1)
        }
        let origin = clamped(originStep, stepCount: stepCount)
        guard stepCount > 0 else { return (bottom: 0, height: 0) }
        if origin == 0 { return (bottom: 0, height: centre(step)) }
        let low = min(centre(origin), centre(step)), high = max(centre(origin), centre(step))
        return (bottom: low, height: high - low)
    }

    nonisolated private static func clamped(_ step: Int, stepCount: Int) -> Int {
        min(max(step, 0), max(stepCount - 1, 0))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Capsule()
                .fill(.secondary.opacity(0.35))
                .frame(width: trackWidth, height: length)
            let span = Self.fill(originStep: originStep, step: shownStep, stepCount: stepCount, length: length, thumb: Theme.Size.sliderThumb)
            Capsule()
                .fill(isAutomatic ? AnyShapeStyle(.secondary) : AnyShapeStyle(Theme.accent))
                .frame(width: trackWidth, height: span.height)
                .offset(y: -span.bottom)
            Circle()
                .fill(.white)
                .opacity(isAutomatic || step == nil ? 0.6 : 1)
                .frame(width: Theme.Size.sliderThumb, height: Theme.Size.sliderThumb)
                .offset(y: -travel * fraction)
        }
        .frame(width: Theme.Size.minTarget, height: length)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    let start = dragStart ?? shownStep
                    dragStart = start
                    let next = Self.step(from: start, translation: drag.translation.height, travel: travel, stepCount: stepCount)
                    guard Self.sends(next, start: start, lastSent: lastSent) else { return }
                    lastSent = next
                    onChange(next)
                }
                .onEnded { _ in
                    dragStart = nil
                    lastSent = nil
                }
        )
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(valueText)
        .accessibilityAdjustableAction { direction in
            let stride = max(adjustStride, 1)
            switch direction {
            case .increment: onChange(Self.clamped(shownStep + stride, stepCount: stepCount))
            case .decrement: onChange(Self.clamped(shownStep - stride, stepCount: stepCount))
            @unknown default: break
            }
        }
    }
}
