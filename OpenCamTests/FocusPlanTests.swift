import Testing
@testable import OpenCam

@Suite struct FocusPlanTests {
    let everything = FocusSupport(focusPoint: true, exposurePoint: true, autoFocusOnce: true, continuousFocus: true, autoExposeOnce: true, continuousExposure: true)
    let point = FocusPoint(x: 0.3, y: 0.6)

    var focusByHand: ManualSettings { var m = ManualSettings(); m.focus = 0.4; return m }
    var exposureByHand: ManualSettings { var m = ManualSettings(); m.exposure = .manual(shutterSeconds: 0.01, iso: nil); return m }

    @Test func aTapSetsBothPointsAndWatchesTheScene() {
        let plan = FocusPlan.make(.point(point), manual: nil, support: everything)
        #expect(plan.focusPoint == point); #expect(plan.focusMode == .once)
        #expect(plan.exposurePoint == point); #expect(plan.exposureMode == .once)
        #expect(plan.watchesSubjectArea); #expect(plan.outcome == .focusAndExposure)
    }

    @Test func aManualFocusKeepsFocusAndMovesOnlyExposure() {
        let plan = FocusPlan.make(.point(point), manual: focusByHand, support: everything)
        #expect(plan.focusPoint == nil); #expect(plan.focusMode == nil)
        #expect(plan.exposurePoint == point); #expect(plan.exposureMode == .once)
        #expect(plan.outcome == .exposureOnly); #expect(plan.watchesSubjectArea)
    }

    @Test func aManualExposureKeepsExposureAndMovesOnlyFocus() {
        let plan = FocusPlan.make(.point(point), manual: exposureByHand, support: everything)
        #expect(plan.exposurePoint == nil); #expect(plan.exposureMode == nil)
        #expect(plan.focusPoint == point); #expect(plan.focusMode == .once)
        #expect(plan.outcome == .focusOnly)
    }

    @Test func bothManualDoesNothing() {
        var both = focusByHand
        both.exposure = .manual(shutterSeconds: nil, iso: 100)
        let plan = FocusPlan.make(.point(point), manual: both, support: everything)
        #expect(plan.focusPoint == nil && plan.exposurePoint == nil)
        #expect(plan.outcome == .nothing); #expect(!plan.watchesSubjectArea)
    }

    @Test func aCameraThatCannotFocusAtAPointMetersOnly() {
        var support = everything
        support.focusPoint = false
        let plan = FocusPlan.make(.point(point), manual: nil, support: support)
        #expect(plan.focusPoint == nil && plan.focusMode == nil)
        #expect(plan.exposurePoint == point)
        #expect(plan.outcome == .exposureOnly)
    }

    @Test func aHoldDoesItOnceAndStopsWatching() {
        let plan = FocusPlan.make(.lock(point), manual: nil, support: everything)
        #expect(plan.focusMode == .once); #expect(plan.exposureMode == .once)
        #expect(plan.focusPoint == point); #expect(plan.exposurePoint == point)
        #expect(!plan.watchesSubjectArea)
    }

    @Test func recentreIsContinuousAtTheCentre() {
        let plan = FocusPlan.make(.recentre, manual: nil, support: everything)
        #expect(plan.focusPoint == .centre); #expect(plan.exposurePoint == .centre)
        #expect(plan.focusMode == .continuous); #expect(plan.exposureMode == .continuous)
        #expect(!plan.watchesSubjectArea)
    }

    @Test func onceFallsBackToContinuous() {
        var support = everything
        support.autoFocusOnce = false
        support.autoExposeOnce = false
        let plan = FocusPlan.make(.point(point), manual: nil, support: support)
        #expect(plan.focusMode == .continuous); #expect(plan.exposureMode == .continuous)
        #expect(plan.outcome == .focusAndExposure)
    }

    @Test func withoutAnySupportThereIsNothing() {
        for request in [FocusRequest.point(point), .lock(point), .recentre] {
            let plan = FocusPlan.make(request, manual: nil, support: FocusSupport())
            #expect(plan.outcome == .nothing); #expect(!plan.watchesSubjectArea)
            #expect(plan.focusPoint == nil && plan.exposurePoint == nil)
        }
    }
}
