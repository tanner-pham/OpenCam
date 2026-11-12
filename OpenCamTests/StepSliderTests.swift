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
}
