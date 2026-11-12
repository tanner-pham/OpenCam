import CoreGraphics
import Testing
@testable import OpenCam

@Suite struct StepSliderTests {
    @Test func aDragMovesByDistanceNotToTheFinger() {
        // Up is negative in the drag's translation: 50 pt up over 200 pt of travel is a quarter of the 20 gaps.
        #expect(StepSlider.step(from: 10, translation: -50, travel: 200, stepCount: 21) == 15)
        #expect(StepSlider.step(from: 10, translation: 50, travel: 200, stepCount: 21) == 5)
    }

    @Test func aTouchAloneChangesNothing() {
        #expect(StepSlider.step(from: 7, translation: 0, travel: 200, stepCount: 21) == 7)
        #expect(StepSlider.step(from: 0, translation: 0, travel: 200, stepCount: 21) == 0)
    }

    @Test func aDragStopsAtBothEnds() {
        #expect(StepSlider.step(from: 10, translation: -5000, travel: 200, stepCount: 21) == 20)
        #expect(StepSlider.step(from: 10, translation: 5000, travel: 200, stepCount: 21) == 0)
    }

    @Test func oneStepNeverDividesByZero() {
        #expect(StepSlider.step(from: 0, translation: -80, travel: 200, stepCount: 1) == 0)
        #expect(StepSlider.step(from: 3, translation: -80, travel: 200, stepCount: 1) == 0)
        #expect(StepSlider.step(from: 5, translation: -80, travel: 0, stepCount: 21) == 5)
        #expect(StepSlider.step(from: 0, translation: -80, travel: 200, stepCount: 0) == 0)
    }

    /// A drag that goes up and comes back to the step it started on sends that step again; a touch alone sends nothing,
    /// and the same step is never sent twice in a row.
    @Test func aDragBackToItsStartIsSent() {
        #expect(!StepSlider.sends(10, start: 10, lastSent: nil))
        #expect(StepSlider.sends(12, start: 10, lastSent: nil))
        #expect(!StepSlider.sends(12, start: 10, lastSent: 12))
        #expect(StepSlider.sends(10, start: 10, lastSent: 12))
    }

    // The scale below: 21 steps on a 200 pt track with a 28 pt thumb, so 172 pt of thumb travel and 8.6 pt per step.
    private func fill(origin: Int, step: Int) -> (bottom: CGFloat, height: CGFloat) {
        StepSlider.fill(originStep: origin, step: step, stepCount: 21, length: 200, thumb: 28)
    }

    /// From step 0 the fill is what it always was: from the track's bottom to the thumb's centre.
    @Test func fillFromTheBottomIsUnchanged() {
        #expect(fill(origin: 0, step: 0) == (bottom: 0, height: 14))
        #expect(fill(origin: 0, step: 10) == (bottom: 0, height: 14 + 86))
        #expect(fill(origin: 0, step: 20) == (bottom: 0, height: 14 + 172))
    }

    /// EV's zero is the middle step: above it the fill runs up from the middle, below it down from the middle.
    @Test func fillRunsFromTheOriginToTheThumb() {
        #expect(fill(origin: 10, step: 15) == (bottom: 14 + 86, height: 43))
        #expect(fill(origin: 10, step: 5) == (bottom: 14 + 43, height: 43))
        #expect(fill(origin: 10, step: 20) == (bottom: 14 + 86, height: 86))
        #expect(fill(origin: 10, step: 0) == (bottom: 14, height: 86))
    }

    @Test func noFillAtTheOrigin() {
        #expect(fill(origin: 10, step: 10).height == 0)
    }

    @Test func aMissingScaleDrawsNoFillPastTheBottom() {
        let one = StepSlider.fill(originStep: 0, step: 0, stepCount: 1, length: 200, thumb: 28)
        #expect(one == (bottom: 0, height: 14))
        let none = StepSlider.fill(originStep: 5, step: 5, stepCount: 0, length: 200, thumb: 28)
        #expect(none.height == 0)
    }

    /// Only EV is centred on its zero; the other scales start at their bottom step.
    @Test func originStepIsEVsZeroAndTheBottomForTheRest() {
        let bias = ManualScale(values: [-2, -1, 0, 1, 2], detentStride: 1, adjustStride: 1, isLogarithmic: false)
        #expect(ControlSlider.originStep(for: .bias, scale: bias) == 2)
        let uneven = ManualScale(values: [-1.5, -1, -0.5, 0, 0.5, 1, 2], detentStride: 1, adjustStride: 1, isLogarithmic: false)
        #expect(ControlSlider.originStep(for: .bias, scale: uneven) == 3)
        #expect(ControlSlider.originStep(for: .shutter, scale: bias) == 0)
        #expect(ControlSlider.originStep(for: .focus, scale: bias) == 0)
    }
}
