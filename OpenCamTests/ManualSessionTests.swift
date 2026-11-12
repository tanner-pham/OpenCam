import CoreMedia
import Foundation
import Testing
@testable import OpenCam

@Suite struct ManualSessionTests {
    private let full = ManualRanges(shutterSeconds: (1.0 / 8000)...(1.0 / 3), iso: 34...6400, bias: -2...2, hasWhiteBalance: true, hasFocus: true)
    private let live = LiveReadouts()

    private func make(_ settings: ManualSettings, applied: ManualSettings? = .automatic, limits: ManualRanges? = nil,
                      isRAWClipRecording: Bool = false) throws(ManualControlError) -> ManualApplyPlan {
        try ManualApplyPlan.make(settings, applied: applied, limits: limits ?? full, lens: "front", isRAWClipRecording: isRAWClipRecording)
    }

    @Test func thePlanSetsOnlyWhatChanged() throws {
        let focused = ManualSettings.automatic.setting(.focus, to: 0.5, live: live)
        let plan = try make(focused)
        #expect(plan.focus == .locked(0.5))
        #expect(plan.exposure == nil && plan.bias == nil && plan.whiteBalance == nil)
        #expect(plan.applied == focused)
        let nothing = try make(focused, applied: focused)
        #expect(nothing.exposure == nil && nothing.bias == nil && nothing.whiteBalance == nil && nothing.focus == nil)
        let released = try make(.automatic, applied: focused)
        #expect(released.focus == .continuous)
        #expect(released.exposure == nil && released.whiteBalance == nil)
    }

    @Test func thePlanSetsEverythingWhenNothingIsKnown() throws {
        let plan = try make(.automatic, applied: nil)
        #expect(plan.exposure == .continuous && plan.whiteBalance == .continuous && plan.focus == .continuous)
        #expect(plan.bias == nil)
        #expect(plan.applied == .automatic)
        let biased = try make(ManualSettings.automatic.setting(.bias, to: 1, live: live), applied: nil)
        #expect(biased.bias == 1)
        var everything = ManualSettings.automatic.setting(.shutter, to: 0.01, live: live).setting(.iso, to: 400, live: live)
        everything = everything.setting(.temperature, to: 5000, live: live).setting(.focus, to: 0.3, live: live)
        let all = try make(everything, applied: nil)
        #expect(all.exposure == .custom(seconds: 0.01, iso: 400))
        #expect(all.whiteBalance == .locked(kelvin: 5000, tint: 0))
        #expect(all.focus == .locked(0.3))
    }

    @Test func everyNumberInThePlanIsInsideTheLimits() throws {
        var settings = ManualSettings()
        settings.exposure = .manual(shutterSeconds: 9, iso: 90_000)
        settings.bias = 7
        settings.whiteBalance = .manual(kelvin: 99_999, tint: 900)
        settings.focus = 3
        let plan = try make(settings, applied: nil)
        #expect(plan.exposure == .custom(seconds: 1.0 / 3, iso: 6400))
        #expect(plan.whiteBalance == .locked(kelvin: 10000, tint: 150))
        #expect(plan.focus == .locked(1))
        settings.exposure = .manual(shutterSeconds: .nan, iso: nil)
        #expect(try make(settings, applied: nil).exposure == .custom(seconds: nil, iso: nil))
    }

    @Test func biasIsSetOnlyWhileExposureIsAutomatic() throws {
        let biased = ManualSettings.automatic.setting(.bias, to: 1, live: live)
        #expect(try make(biased).bias == 1)
        let manual = biased.setting(.iso, to: 400, live: live)
        let whileManual = try make(manual)
        #expect(whileManual.exposure == .custom(seconds: nil, iso: 400))
        #expect(whileManual.bias == nil)
        // The device keeps the bias it has; it is the one the plan remembers, so Auto sets the new one.
        #expect(whileManual.applied.bias == nil)
        let back = try make(biased, applied: whileManual.applied)
        #expect(back.exposure == .continuous)
        #expect(back.bias == 1)
        #expect(back.applied == biased)
        // Never set here, so the camera's own bias is left alone.
        #expect(try make(.automatic, applied: biased).bias == nil)
    }

    @Test func aControlTheCameraLacksThrowsBeforeAnythingIsSet() {
        let focus = ManualSettings.automatic.setting(.focus, to: 0.4, live: live)
        var noFocus = full
        noFocus.hasFocus = false
        #expect(throws: ManualControlError.notSupported(control: "focus", lens: "front")) { try make(focus, limits: noFocus) }
        #expect(throws: ManualControlError.notSupported(control: "exposure", lens: "front")) {
            try make(ManualSettings.automatic.setting(.iso, to: 100, live: live), limits: ManualRanges())
        }
        #expect(throws: ManualControlError.notSupported(control: "white balance", lens: "front")) {
            try make(ManualSettings.automatic.setting(.tint, to: 1, live: live), limits: ManualRanges())
        }
        #expect(throws: ManualControlError.notSupported(control: "bias", lens: "front")) {
            try make(ManualSettings.automatic.setting(.bias, to: 1, live: live), limits: ManualRanges())
        }
        // Automatic needs nothing from the camera.
        #expect(throws: Never.self) { try make(.automatic, applied: nil, limits: ManualRanges()) }
    }

    @Test func gainsStayBetweenOneAndTheMaximum() {
        #expect(ManualApplyPlan.clampedGain(0.4, max: 4) == 1)
        #expect(ManualApplyPlan.clampedGain(9, max: 4) == 4)
        #expect(ManualApplyPlan.clampedGain(2.5, max: 4) == 2.5)
        #expect(ManualApplyPlan.clampedGain(.nan, max: 4) == 1)
        #expect(ManualApplyPlan.clampedGain(.infinity, max: 4) == 4)
        #expect(ManualApplyPlan.clampedGain(-.infinity, max: 4) == 1)
        #expect(ManualApplyPlan.clampedGain(2, max: .nan) == 1)
        #expect(ManualApplyPlan.clampedGain(2, max: 0.5) == 1)
    }

    @Test func aShutterIsClampedOnCMTimeAgainstTheFormatsLimits() {
        let low = CMTime(value: 1, timescale: 8000)
        let high = CMTime(value: 1, timescale: 24)
        // A double a hair over the limit converts to one tick past it (41666667 against 41666666), and lands on the limit.
        let tick = CMTime(value: 41_666_666, timescale: 1_000_000_000)
        #expect(ManualApplyPlan.clampedDuration(0.0416666675, minimum: low, maximum: tick) == tick)
        #expect(ManualApplyPlan.clampedDuration(1.0 / 24, minimum: low, maximum: high).map { $0 <= high } == true)
        #expect(ManualApplyPlan.clampedDuration(5, minimum: low, maximum: high) == high)
        #expect(ManualApplyPlan.clampedDuration(1e-9, minimum: low, maximum: high) == low)
        #expect(ManualApplyPlan.clampedDuration(-1, minimum: low, maximum: high) == low)
        let inside = ManualApplyPlan.clampedDuration(0.01, minimum: low, maximum: high)
        #expect(inside.map { $0 >= low && $0 <= high } == true)
        #expect(ManualApplyPlan.clampedDuration(.nan, minimum: low, maximum: high) == nil)
        #expect(ManualApplyPlan.clampedDuration(0.01, minimum: .invalid, maximum: high) == nil)
        #expect(ManualApplyPlan.clampedDuration(0.01, minimum: low, maximum: .positiveInfinity) == nil)
        // A format whose limits are reversed never lets a value above the upper one through.
        #expect(ManualApplyPlan.clampedDuration(0.01, minimum: high, maximum: low) == low)
    }

    @Test func plainNumbersAreClampedIntoTheirRange() {
        #expect(ManualApplyPlan.clampedValue(9000, lower: 34, upper: 6400) == 6400)
        #expect(ManualApplyPlan.clampedValue(1, lower: 34, upper: 6400) == 34)
        #expect(ManualApplyPlan.clampedValue(.nan, lower: 34, upper: 6400) == 34)
        #expect(ManualApplyPlan.clampedValue(0.5, lower: 0, upper: 1) == 0.5)
        #expect(ManualApplyPlan.clampedValue(9000, lower: 6400, upper: 34) == 6400)
    }

    @Test func whiteBalanceAroundARAWClip() throws {
        let byHand = ManualSettings.automatic.setting(.temperature, to: 4000, live: live)
        // Set by hand during the clip: the lock stays, and the clip's own restore must not undo it.
        #expect(try make(byHand, isRAWClipRecording: true).whiteBalance == .locked(kelvin: 4000, tint: 0))
        // Auto during the clip: stays locked until the clip ends.
        #expect(try make(.automatic, applied: byHand, isRAWClipRecording: true).whiteBalance == .continuousAfterClip)
        // Auto otherwise.
        #expect(try make(.automatic, applied: byHand, isRAWClipRecording: false).whiteBalance == .continuous)
        #expect(try make(.automatic, applied: nil, isRAWClipRecording: false).whiteBalance == .continuous)
        // A clip changes nothing for a white balance that did not change.
        #expect(try make(byHand, applied: byHand, isRAWClipRecording: true).whiteBalance == nil)
    }

    @Test func aPhotoReturnsTheFrameDurationWhenExposureChanges() throws {
        let manual = ManualSettings.automatic.setting(.iso, to: 100, live: live)
        #expect(try make(manual, limits: full).restoresFrameDuration)
        #expect(try make(.automatic, applied: manual, limits: full).restoresFrameDuration)
        #expect(try !make(.automatic, applied: .automatic, limits: full).restoresFrameDuration)
        var video = full
        video.frameSeconds = 1.0 / 30
        #expect(try !make(manual, limits: video).restoresFrameDuration)
    }

    @Test func errorsReadInTheHouseFormat() {
        #expect(ManualControlError.noCamera.description == "[CameraSession:applyManual] No running camera — {running: false}")
        #expect(ManualControlError.lockFailed(reason: "busy").description
                == "[CameraSession:applyManual] Cannot lock the camera for configuration — {reason: busy}")
        #expect(ManualControlError.notSupported(control: "focus", lens: "front").description
                == "[CameraSession:applyManual] Control not supported by this camera — {control: focus, lens: front}")
    }

    @Test func theFakeRecordsEachApplyAndClampsLikeTheSession() async throws {
        let fake = FakeSessionConfigurator(failingLensIDs: [])
        await fake.setRanges(full)
        await fake.setReadouts(LiveReadouts(iso: 200))
        #expect(await fake.manualRanges() == full)
        #expect(await fake.currentReadouts() == LiveReadouts(iso: 200))
        var settings = ManualSettings()
        settings.exposure = .manual(shutterSeconds: 9, iso: 90_000)
        settings.focus = 3
        let result = try await fake.applyManual(settings, reapplyingAll: false)
        #expect(result == full.clamped(settings))
        #expect(result.focus == 1)
        _ = try await fake.applyManual(.automatic, reapplyingAll: true)
        let applies = await fake.manualApplies
        #expect(applies.map(\.settings) == [settings, .automatic])
        #expect(applies.map(\.reapplyingAll) == [false, true])
        #expect(await fake.calls == ["manual", "manual"])
        await fake.setManualError(.noCamera)
        await #expect(throws: ManualControlError.noCamera) { try await fake.applyManual(.automatic, reapplyingAll: false) }
        await fake.setManualError(nil)
        await fake.setRanges(nil)
        #expect(await fake.manualRanges() == nil)
    }

    @Test func aHeldApplyWaitsUntilItIsResumed() async throws {
        let fake = FakeSessionConfigurator(failingLensIDs: [])
        await fake.setRanges(full)
        await fake.holdManual()
        let pending = Task { try await fake.applyManual(.automatic, reapplyingAll: false) }
        for _ in 0..<200 where await fake.manualApplies.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        #expect(await fake.manualApplies.count == 1)
        await fake.resumeManual()
        _ = try await pending.value
        #expect(await fake.manualApplies.count == 1)
    }
}
