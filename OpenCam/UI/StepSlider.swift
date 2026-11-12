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
    var length = Theme.Size.sliderLength
    let onChange: (Int) -> Void

    /// The step the current drag started from; nil between drags.
    @State private var dragStart: Int?

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

    nonisolated private static func clamped(_ step: Int, stepCount: Int) -> Int {
        min(max(step, 0), max(stepCount - 1, 0))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Capsule()
                .fill(.secondary.opacity(0.35))
                .frame(width: trackWidth, height: length)
            Capsule()
                .fill(isAutomatic ? AnyShapeStyle(.secondary) : AnyShapeStyle(Theme.accent))
                .frame(width: trackWidth, height: Theme.Size.sliderThumb / 2 + travel * fraction)
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
                    if next != start, next != step { onChange(next) }
                }
                .onEnded { _ in dragStart = nil }
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
