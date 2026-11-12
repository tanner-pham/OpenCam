import CoreMedia
import Foundation
import Testing
@testable import OpenCam

/// Every decision the device code used to make, as plain values: the limits read off a camera in, the exact request out.
@Suite struct ManualDeviceRequestTests {
    private let fast = CMTime(value: 1, timescale: 8000)
    private let slow = CMTime(value: 1, timescale: 3)
    private let frame = CMTime(value: 1, timescale: 30)

    private func limits(isVideo: Bool = false, frame: CMTime = .invalid) -> DeviceLimits {
        DeviceLimits(minExposureDuration: fast, maxExposureDuration: slow, frameDuration: frame, minISO: 34, maxISO: 6400,
                     minBias: -8, maxBias: 8, recommendedBias: -2...2, maxWhiteBalanceGain: 4, isVideo: isVideo,
                     supportsContinuousExposure: true, supportsCustomExposure: true,
                     supportsContinuousWhiteBalance: true, supportsLockedWhiteBalance: true, supportsCustomGains: true,
                     supportsContinuousFocus: true, supportsLockedFocus: true, supportsCustomLensPosition: true)
    }

    private func plan(exposure: ManualApplyPlan.Exposure? = nil, bias: Float? = nil, whiteBalance: ManualApplyPlan.WhiteBalance? = nil,
                      focus: ManualApplyPlan.Focus? = nil, restoresFrameDuration: Bool = false) -> ManualApplyPlan {
        ManualApplyPlan(exposure: exposure, bias: bias, whiteBalance: whiteBalance, focus: focus,
                        restoresFrameDuration: restoresFrameDuration, applied: .automatic)
    }

    // MARK: Exposure

    @Test func aShutterAboveTheFrameTimeInVideoStopsAtTheFrameTime() {
        let request = ManualDeviceRequest.make(plan(exposure: .custom(seconds: 0.2, iso: nil)), limits: limits(isVideo: true, frame: frame))
        #expect(request.exposure == .custom(duration: frame, iso: nil))
        #expect(request.clamps.map(\.control) == ["shutter"])
        // Photo has no frame time: the format's longest exposure is the limit.
        let photo = ManualDeviceRequest.make(plan(exposure: .custom(seconds: 0.2, iso: nil)), limits: limits())
        #expect(photo.exposure == .custom(duration: CMTime(seconds: 0.2, preferredTimescale: 1_000_000_000), iso: nil))
        let tooLong = ManualDeviceRequest.make(plan(exposure: .custom(seconds: 5, iso: nil)), limits: limits())
        #expect(tooLong.exposure == .custom(duration: slow, iso: nil))
    }

    @Test func aVideoWithoutAFrameTimeKeepsTheFormatsLongestExposure() {
        let request = ManualDeviceRequest.make(plan(exposure: .custom(seconds: 5, iso: nil)), limits: limits(isVideo: true, frame: .invalid))
        #expect(request.exposure == .custom(duration: slow, iso: nil))
    }

    @Test func aMissingShutterOrISOBecomesTheCamerasCurrentValue() {
        let both = ManualDeviceRequest.make(plan(exposure: .custom(seconds: nil, iso: nil)), limits: limits())
        #expect(both.exposure == .custom(duration: nil, iso: nil))
        let isoOnly = ManualDeviceRequest.make(plan(exposure: .custom(seconds: nil, iso: 99_999)), limits: limits())
        #expect(isoOnly.exposure == .custom(duration: nil, iso: 6400))
        #expect(isoOnly.clamps == [ManualDeviceRequest.Clamp(control: "iso", asked: 99_999, set: 6400)])
        let low = ManualDeviceRequest.make(plan(exposure: .custom(seconds: 1e-9, iso: 1)), limits: limits())
        #expect(low.exposure == .custom(duration: fast, iso: 34))
    }

    @Test func aShutterInsideTheLimitsIsNotLogged() {
        let request = ManualDeviceRequest.make(plan(exposure: .custom(seconds: 1.0 / 60, iso: 400)), limits: limits())
        #expect(request.clamps.isEmpty)
        #expect(request.exposure == .custom(duration: CMTime(seconds: 1.0 / 60, preferredTimescale: 1_000_000_000), iso: 400))
    }

    @Test func nonFiniteNumbersNeverReachTheDevice() {
        let request = ManualDeviceRequest.make(plan(exposure: .custom(seconds: .nan, iso: .infinity), bias: .nan,
                                                    whiteBalance: .locked(kelvin: .nan, tint: 0), focus: .locked(.infinity)),
                                               limits: limits())
        #expect(request.exposure == .custom(duration: nil, iso: nil))
        #expect(request.bias == nil)
        #expect(request.whiteBalance == nil && request.restore == .leave)
        #expect(request.focus == nil)
        let tint = ManualDeviceRequest.make(plan(whiteBalance: .locked(kelvin: 5000, tint: -.infinity)), limits: limits())
        #expect(tint.whiteBalance == nil)
        let seconds = ManualDeviceRequest.make(plan(exposure: .custom(seconds: -.infinity, iso: nil)), limits: limits())
        #expect(seconds.exposure == .custom(duration: nil, iso: nil))
    }

    @Test func aModeTheDeviceLacksProducesNoAction() {
        var none = limits()
        none.supportsContinuousExposure = false
        none.supportsCustomExposure = false
        none.supportsContinuousWhiteBalance = false
        none.supportsLockedWhiteBalance = false
        none.supportsContinuousFocus = false
        none.supportsLockedFocus = false
        let all = plan(exposure: .continuous, whiteBalance: .continuous, focus: .continuous)
        let request = ManualDeviceRequest.make(all, limits: none)
        #expect(request.exposure == nil && request.whiteBalance == nil && request.focus == nil)
        let manual = ManualDeviceRequest.make(plan(exposure: .custom(seconds: 0.01, iso: 100), whiteBalance: .locked(kelvin: 5000, tint: 0),
                                                   focus: .locked(0.5)), limits: none)
        #expect(manual.exposure == nil && manual.whiteBalance == nil && manual.focus == nil && manual.restore == .leave)
        none.supportsLockedWhiteBalance = true
        none.supportsCustomGains = false
        #expect(ManualDeviceRequest.make(plan(whiteBalance: .locked(kelvin: 5000, tint: 0)), limits: none).whiteBalance == nil)
        none.supportsLockedFocus = true
        none.supportsCustomLensPosition = false
        #expect(ManualDeviceRequest.make(plan(focus: .locked(0.5)), limits: none).focus == nil)
        let afterClip = ManualDeviceRequest.make(plan(whiteBalance: .continuousAfterClip), limits: none)
        #expect(afterClip.whiteBalance == nil && afterClip.restore == .leave)
    }

    @Test func aPlanWithNothingToSetAsksForNothing() {
        #expect(ManualDeviceRequest.make(plan(), limits: limits()) == ManualDeviceRequest())
    }

    // MARK: Frame duration

    @Test func theFrameDurationIsReleasedOnlyWhenThePlanSaysSoAndAutoFrameRateIsOff() {
        #expect(ManualDeviceRequest.make(plan(exposure: .continuous, restoresFrameDuration: true), limits: limits()).resetsFrameDuration)
        #expect(!ManualDeviceRequest.make(plan(exposure: .continuous, restoresFrameDuration: false), limits: limits()).resetsFrameDuration)
        var autoRate = limits()
        autoRate.isAutoFrameRateEnabled = true
        #expect(!ManualDeviceRequest.make(plan(exposure: .continuous, restoresFrameDuration: true), limits: autoRate).resetsFrameDuration)
        #expect(!ManualDeviceRequest.make(plan(restoresFrameDuration: true), limits: limits()).resetsFrameDuration)
    }

    // MARK: Bias and focus

    @Test func biasAndFocusAreClampedToTheDevicesOwnLimits() {
        let request = ManualDeviceRequest.make(plan(bias: 20, focus: .locked(3)), limits: limits())
        #expect(request.bias == 8)
        #expect(request.focus == .locked(1))
        #expect(request.clamps.map(\.control) == ["bias", "focus"])
        #expect(ManualDeviceRequest.make(plan(bias: 0.5, focus: .locked(0.25)), limits: limits()).clamps.isEmpty)
        #expect(ManualDeviceRequest.make(plan(focus: .continuous), limits: limits()).focus == .continuous)
    }

    // MARK: White balance

    @Test func whiteBalanceActionsAndTheRestoreBookkeeping() {
        let locked = ManualDeviceRequest.make(plan(whiteBalance: .locked(kelvin: 4000, tint: 5)), limits: limits())
        #expect(locked.whiteBalance == .locked(kelvin: 4000, tint: 5, maxGain: 4))
        #expect(locked.restore == .clear)
        let afterClip = ManualDeviceRequest.make(plan(whiteBalance: .continuousAfterClip), limits: limits())
        #expect(afterClip.whiteBalance == .stayLocked)
        #expect(afterClip.restore == .toContinuous)
        let continuous = ManualDeviceRequest.make(plan(whiteBalance: .continuous), limits: limits())
        #expect(continuous.whiteBalance == .continuous)
        #expect(continuous.restore == .leave)
    }

    @Test func gainsStayBetweenOneAndTheMaximum() {
        typealias Gains = ManualDeviceRequest.Gains
        let inside = ManualDeviceRequest.clampedGains(Gains(red: 1, green: 2, blue: 4), max: 4)
        #expect(inside.gains == Gains(red: 1, green: 2, blue: 4) && !inside.wasClamped)
        let moved = ManualDeviceRequest.clampedGains(Gains(red: 0.4, green: 9, blue: 2), max: 4)
        #expect(moved.gains == Gains(red: 1, green: 4, blue: 2) && moved.wasClamped)
        let broken = ManualDeviceRequest.clampedGains(Gains(red: .nan, green: .infinity, blue: -.infinity), max: 4)
        #expect(broken.gains == Gains(red: 1, green: 4, blue: 1) && broken.wasClamped)
        #expect(ManualDeviceRequest.clampedGains(Gains(red: 2, green: 2, blue: 2), max: .nan).gains == Gains(red: 1, green: 1, blue: 1))
    }

    // MARK: Reset and result

    @Test func theResetSetsEachAutomaticModeOnlyWhereSupportedAndBiasZeroOnlyInsideTheLimits() {
        let full = ManualDeviceRequest.resetting(limits())
        #expect(full.exposure == .continuous && full.bias == 0 && full.whiteBalance == .continuous && full.focus == .continuous)
        #expect(!full.resetsFrameDuration && full.restore == .leave)
        var none = limits()
        none.supportsContinuousExposure = false
        none.supportsContinuousWhiteBalance = false
        none.supportsContinuousFocus = false
        none.minBias = 1
        let empty = ManualDeviceRequest.resetting(none)
        #expect(empty == ManualDeviceRequest())
        none.minBias = -1
        none.maxBias = -0.5
        #expect(ManualDeviceRequest.resetting(none).bias == nil)
        none.minBias = .nan
        #expect(ManualDeviceRequest.resetting(none).bias == nil)
    }

    @Test func theResultReportsWhatTheCameraHasNotWhatWasAsked() {
        var asked = ManualSettings()
        asked.exposure = .manual(shutterSeconds: 0.01, iso: 400)
        asked.whiteBalance = .manual(kelvin: 9000, tint: 0)
        let aPlan = ManualApplyPlan(exposure: .custom(seconds: 0.01, iso: 400), applied: asked)
        let took = ManualDeviceRequest.result(of: aPlan, previous: nil, outcome: .init(didSetExposure: true, whiteBalance: nil))
        #expect(took == asked)
        let clamped = ManualDeviceRequest.result(of: aPlan, previous: nil, outcome: .init(didSetExposure: true, whiteBalance: .manual(kelvin: 8000, tint: 2)))
        #expect(clamped.whiteBalance == .manual(kelvin: 8000, tint: 2))
        // An exposure that was not set stays what it was.
        #expect(ManualDeviceRequest.result(of: aPlan, previous: nil, outcome: .init(didSetExposure: false, whiteBalance: nil)).exposure == .automatic)
        var before = ManualSettings()
        before.exposure = .manual(shutterSeconds: 0.5, iso: nil)
        #expect(ManualDeviceRequest.result(of: aPlan, previous: before, outcome: .init(didSetExposure: false, whiteBalance: nil)).exposure == before.exposure)
        // A plan that did not touch exposure keeps the plan's, whatever the device did.
        let other = ManualApplyPlan(focus: .locked(0.5), applied: asked)
        #expect(ManualDeviceRequest.result(of: other, previous: nil, outcome: .init(didSetExposure: false, whiteBalance: nil)).exposure == asked.exposure)
    }

    // MARK: Limits to ranges

    @Test func rangesFollowTheLimitsAndStateTheMode() {
        let photo = ManualRanges.make(from: limits())
        #expect(photo.shutterSeconds == (1.0 / 8000)...(1.0 / 3) && photo.iso == 34...6400)
        #expect(!photo.isVideo && photo.frameSeconds == nil)
        #expect(photo.bias == -2...2 && photo.hasWhiteBalance && photo.hasFocus)
        let video = ManualRanges.make(from: limits(isVideo: true, frame: frame))
        #expect(video.isVideo && video.frameSeconds == 1.0 / 30)
        #expect(video.shutterSeconds == (1.0 / 8000)...(1.0 / 30))
        // A video format whose frame time cannot be read is still video, with the format's own longest exposure.
        let unreadable = ManualRanges.make(from: limits(isVideo: true, frame: .invalid))
        #expect(unreadable.isVideo && unreadable.frameSeconds == nil && unreadable.shutterSeconds == (1.0 / 8000)...(1.0 / 3))
    }

    @Test func rangesLeaveOutWhatTheCameraCannotDo() {
        var none = limits(isVideo: true, frame: frame)
        none.supportsCustomExposure = false
        let noCustom = ManualRanges.make(from: none)
        #expect(noCustom.shutterSeconds == nil && noCustom.iso == nil && noCustom.isVideo)
        var reversed = limits()
        reversed.minISO = 6400
        reversed.maxISO = 34
        #expect(ManualRanges.make(from: reversed).iso == nil)
        var device = limits()
        device.recommendedBias = nil
        #expect(ManualRanges.make(from: device).bias == -8...8)
        device.minBias = 3
        device.maxBias = -3
        #expect(ManualRanges.make(from: device).bias == nil)
        var white = limits()
        white.maxWhiteBalanceGain = 0.5
        #expect(!ManualRanges.make(from: white).hasWhiteBalance)
        white.maxWhiteBalanceGain = 4
        white.supportsCustomGains = false
        #expect(!ManualRanges.make(from: white).hasWhiteBalance)
        var focus = limits()
        focus.supportsCustomLensPosition = false
        #expect(!ManualRanges.make(from: focus).hasFocus)
    }
}
