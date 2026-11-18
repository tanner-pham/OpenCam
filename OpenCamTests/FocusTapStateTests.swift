import CoreGraphics
import Testing
@testable import OpenCam

@Suite struct FocusTapStateTests {
    let geometry = PreviewGeometry.filling(CGSize(width: 400, height: 400))
    let automatic = ManualSettings.automatic
    let a = CGPoint(x: 100, y: 100)
    let b = CGPoint(x: 300, y: 200)

    var focusByHand: ManualSettings { var m = ManualSettings(); m.focus = 0.4; return m }
    var exposureByHand: ManualSettings { var m = ManualSettings(); m.exposure = .manual(shutterSeconds: 0.01, iso: nil); return m }

    @Test func aTapShowsTheMarkerAndAsksForThePoint() {
        var state = FocusTapState()
        let request = state.tapped(at: a, geometry: geometry, manual: automatic)
        #expect(request == .point(FocusPoint(x: 0.25, y: 0.25)))
        #expect(state.marker?.viewPoint == a); #expect(state.marker?.isLocked == false)
        #expect(state.lock == nil); #expect(state.lockText == nil)
    }

    @Test func aSecondTapReplacesTheMarkerAndEndsTheLock() {
        var state = FocusTapState()
        _ = state.tapped(at: a, geometry: geometry, manual: automatic)
        let first = state.marker?.serial ?? 0
        _ = state.held(at: a, geometry: geometry, manual: automatic)
        #expect(state.lock != nil)
        _ = state.tapped(at: b, geometry: geometry, manual: automatic)
        #expect(state.marker?.viewPoint == b); #expect((state.marker?.serial ?? 0) > first)
        #expect(state.lock == nil); #expect(state.marker?.isLocked == false)
    }

    @Test func aHoldLocksAndShowsTheCapsule() {
        var state = FocusTapState()
        let request = state.held(at: a, geometry: geometry, manual: automatic)
        #expect(request == .lock(FocusPoint(x: 0.25, y: 0.25)))
        #expect(state.marker?.isLocked == true); #expect(state.lock == .focusAndExposure)
        #expect(state.lockText == "AE/AF lock")
    }

    @Test func aHoldWithFocusSetByHandReadsAELock() {
        var state = FocusTapState()
        _ = state.held(at: a, geometry: geometry, manual: focusByHand)
        #expect(state.lockText == "AE lock")
        var other = FocusTapState()
        _ = other.held(at: a, geometry: geometry, manual: exposureByHand)
        #expect(other.lockText == "AF lock")
    }

    @Test func withBothSetByHandATapShowsNothingAndAsksNothing() {
        var both = focusByHand
        both.exposure = .manual(shutterSeconds: nil, iso: 100)
        var state = FocusTapState()
        #expect(state.tapped(at: a, geometry: geometry, manual: both) == nil)
        #expect(state.held(at: a, geometry: geometry, manual: both) == nil)
        #expect(state.marker == nil); #expect(state.lock == nil)
    }

    @Test func aTapOutsideThePictureShowsNothing() {
        let bars = PreviewGeometry(viewSize: CGSize(width: 1600, height: 900), sensorSize: CGSize(width: 4, height: 3), rotation: 0, isMirrored: false)
        var state = FocusTapState()
        #expect(state.tapped(at: CGPoint(x: 10, y: 450), geometry: bars, manual: automatic) == nil)
        #expect(state.held(at: CGPoint(x: 10, y: 450), geometry: bars, manual: automatic) == nil)
        #expect(state.marker == nil); #expect(state.lock == nil)
    }

    @Test func aManualChangeWhileLockedRecentres() {
        var state = FocusTapState()
        _ = state.held(at: a, geometry: geometry, manual: automatic)
        #expect(state.manualChanged() == .recentre)
        #expect(state.lock == nil); #expect(state.lockText == nil); #expect(state.marker == nil)
        #expect(state.manualChanged() == nil)
    }

    @Test func aManualChangeUnlockedAsksNothing() {
        var state = FocusTapState()
        _ = state.tapped(at: a, geometry: geometry, manual: automatic)
        #expect(state.manualChanged() == nil)
        #expect(state.marker?.viewPoint == a)
    }

    @Test func aCameraChangeClearsEverything() {
        var state = FocusTapState()
        _ = state.held(at: a, geometry: geometry, manual: automatic)
        state.cameraChanged()
        #expect(state.marker == nil); #expect(state.lock == nil); #expect(state.lockText == nil)
    }

    @Test func onlyTheLatestMarkerFades() {
        var state = FocusTapState()
        _ = state.tapped(at: a, geometry: geometry, manual: automatic)
        let old = state.marker?.serial ?? 0
        _ = state.tapped(at: b, geometry: geometry, manual: automatic)
        state.markerFaded(serial: old)
        #expect(state.marker?.viewPoint == b)
        state.markerFaded(serial: state.marker?.serial ?? 0)
        #expect(state.marker == nil)
        _ = state.held(at: a, geometry: geometry, manual: automatic)
        state.markerFaded(serial: state.marker?.serial ?? 0)
        #expect(state.marker?.isLocked == true)
    }

    @Test func noStringHasAnEmDash() {
        for manual in [automatic, focusByHand, exposureByHand] {
            var state = FocusTapState()
            _ = state.held(at: a, geometry: geometry, manual: manual)
            #expect(state.lockText?.contains("\u{2014}") == false)
        }
    }
}
