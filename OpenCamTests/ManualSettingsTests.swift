import Foundation
import Testing
@testable import OpenCam

@Suite struct ManualSettingsTests {
    private let live = LiveReadouts(iso: 200, shutterSeconds: 1.0 / 60, kelvin: 4800, tint: 7, exposureBias: 0.3, lensPosition: 0.4)
    private let none = LiveReadouts()
    private let full = ManualRanges(shutterSeconds: (1.0 / 8000)...(1.0 / 3), iso: 34...6400, bias: -2...2, hasWhiteBalance: true, hasFocus: true)

    @Test func theFirstMoveOfShutterOrISOLocksBothAndHoldsTheOther() {
        let shutter = ManualSettings.automatic.setting(.shutter, to: 0.01, live: live)
        #expect(shutter.exposure == .manual(shutterSeconds: 0.01, iso: nil))
        let iso = ManualSettings.automatic.setting(.iso, to: 800, live: live)
        #expect(iso.exposure == .manual(shutterSeconds: nil, iso: 800))
        let both = shutter.setting(.iso, to: 400, live: live)
        #expect(both.exposure == .manual(shutterSeconds: 0.01, iso: 400))
        #expect(both.setting(.shutter, to: 0.02, live: live).exposure == .manual(shutterSeconds: 0.02, iso: 400))
        #expect(!shutter.isAutomatic)
    }

    @Test func autoOnEitherReturnsBoth() {
        let set = ManualSettings.automatic.setting(.shutter, to: 0.01, live: live).setting(.iso, to: 400, live: live)
        #expect(set.settingAutomatic(.shutter).exposure == .automatic)
        #expect(set.settingAutomatic(.iso).exposure == .automatic)
        let balanced = ManualSettings.automatic.setting(.temperature, to: 5000, live: live)
        #expect(balanced.settingAutomatic(.temperature).whiteBalance == .automatic)
        #expect(balanced.settingAutomatic(.tint).whiteBalance == .automatic)
        let biased = ManualSettings.automatic.setting(.bias, to: 1, live: live)
        #expect(biased.settingAutomatic(.bias) == biased)
    }

    @Test func evIsNotAdjustableWhileExposureIsManualAndReadsMissing() {
        let biased = ManualSettings.automatic.setting(.bias, to: 1, live: live)
        #expect(biased.isAdjustable(.bias))
        #expect(biased.value(of: .bias, live: live) == 1)
        let manual = biased.setting(.iso, to: 400, live: live)
        #expect(!manual.isAdjustable(.bias))
        #expect(manual.value(of: .bias, live: live) == nil)
        #expect(manual.isAdjustable(.shutter) && manual.isAdjustable(.focus))
        #expect(!manual.isSet(.bias))
        #expect(ManualSettings.automatic.value(of: .bias, live: live) == Double(Float(0.3)))
    }

    @Test func temperatureTakesTintFromTheLiveReadoutAndTintTakesTemperature() {
        let warm = ManualSettings.automatic.setting(.temperature, to: 6000, live: live)
        #expect(warm.whiteBalance == .manual(kelvin: 6000, tint: 7))
        #expect(ManualSettings.automatic.setting(.temperature, to: 6000, live: none).whiteBalance == .manual(kelvin: 6000, tint: 0))
        let green = ManualSettings.automatic.setting(.tint, to: -12, live: live)
        #expect(green.whiteBalance == .manual(kelvin: 4800, tint: -12))
        #expect(ManualSettings.automatic.setting(.tint, to: -12, live: none).whiteBalance == .manual(kelvin: 5600, tint: -12))
        #expect(warm.setting(.tint, to: 3, live: none).whiteBalance == .manual(kelvin: 6000, tint: 3))
        #expect(green.setting(.temperature, to: 3000, live: none).whiteBalance == .manual(kelvin: 3000, tint: -12))
    }

    @Test func focusLocksAndAutoReleases() {
        let locked = ManualSettings.automatic.setting(.focus, to: 0.7, live: live)
        #expect(locked.focus == 0.7)
        #expect(locked.isSet(.focus) && !locked.isAutomatic)
        let released = locked.settingAutomatic(.focus)
        #expect(released.focus == nil && released.isAutomatic)
    }

    @Test func readoutValuesAreLiveInAutoAndTheSetValueByHand() {
        let auto = ManualSettings.automatic
        #expect(auto.value(of: .shutter, live: live) == 1.0 / 60)
        #expect(auto.value(of: .iso, live: live) == 200)
        #expect(auto.value(of: .temperature, live: live) == 4800)
        #expect(auto.value(of: .tint, live: live) == 7)
        #expect(auto.value(of: .focus, live: live) == Double(Float(0.4)))
        #expect(auto.value(of: .shutter, live: none) == nil)
        for control in ManualControl.allCases { #expect(!auto.isSet(control)) }
        let held = auto.setting(.iso, to: 800, live: live)
        #expect(held.value(of: .shutter, live: live) == 1.0 / 60)
        #expect(held.value(of: .iso, live: live) == 800)
        #expect(held.isSet(.shutter) && held.isSet(.iso))
        let wb = auto.setting(.temperature, to: 6000, live: live)
        #expect(wb.value(of: .temperature, live: live) == 6000)
        #expect(wb.value(of: .tint, live: none) == 7)
        #expect(wb.isSet(.temperature) && wb.isSet(.tint))
        #expect(auto.setting(.focus, to: 0.7, live: live).value(of: .focus, live: none) == Double(Float(0.7)))
    }

    @Test func biasDoesNotCountAsManual() {
        let biased = ManualSettings.automatic.setting(.bias, to: 1, live: live)
        #expect(biased.isAutomatic)
    }

    @Test func clampingKeepsEveryValueInsideItsRange() {
        var settings = ManualSettings()
        settings.exposure = .manual(shutterSeconds: 5, iso: 100_000)
        settings.bias = 9
        settings.whiteBalance = .manual(kelvin: 20000, tint: -400)
        settings.focus = 1.2
        let clamped = full.clamped(settings)
        #expect(clamped.exposure == .manual(shutterSeconds: 1.0 / 3, iso: 6400))
        #expect(clamped.bias == 2)
        #expect(clamped.whiteBalance == .manual(kelvin: 10000, tint: -150))
        #expect(clamped.focus == 1)

        settings.exposure = .manual(shutterSeconds: 0.000001, iso: 1)
        settings.whiteBalance = .manual(kelvin: 100, tint: 400)
        settings.focus = -1
        settings.bias = -9
        let low = full.clamped(settings)
        #expect(low.exposure == .manual(shutterSeconds: 1.0 / 8000, iso: 34))
        #expect(low.whiteBalance == .manual(kelvin: 2500, tint: 150))
        #expect(low.focus == 0 && low.bias == -2)

        var broken = ManualSettings()
        broken.exposure = .manual(shutterSeconds: .nan, iso: .infinity)
        broken.bias = .nan
        broken.focus = .nan
        let fixed = full.clamped(broken)
        #expect(fixed.exposure == .manual(shutterSeconds: nil, iso: nil))
        #expect(fixed.bias == nil && fixed.focus == nil)
        broken.whiteBalance = .manual(kelvin: .nan, tint: 0)
        #expect(full.clamped(broken).whiteBalance == .automatic)
        broken.whiteBalance = .manual(kelvin: 5000, tint: .infinity)
        #expect(full.clamped(broken).whiteBalance == .automatic)

        let lacking = ManualRanges()
        let all = lacking.clamped(settings)
        #expect(all == .automatic)
        #expect(all.bias == nil && all.focus == nil)
    }

    @Test func clampingLeavesValuesInsideTheRangeAlone() {
        var settings = ManualSettings()
        settings.exposure = .manual(shutterSeconds: 0.01, iso: 400)
        settings.bias = 0.5
        settings.whiteBalance = .manual(kelvin: 5600, tint: 4)
        settings.focus = 0.3
        #expect(full.clamped(settings) == settings)
    }

    @Test func aVideoShutterNeverExceedsTheFrameTime() {
        var ranges = full
        ranges.shutterSeconds = (1.0 / 8000)...(1.0 / 24)
        ranges.frameSeconds = 1.0 / 24
        var settings = ManualSettings()
        settings.exposure = .manual(shutterSeconds: 0.2, iso: nil)
        #expect(ranges.clamped(settings).exposure == .manual(shutterSeconds: 1.0 / 24, iso: nil))
        ranges.shutterSeconds = (1.0 / 8000)...(1.0 / 3)
        #expect(ranges.clamped(settings).exposure == .manual(shutterSeconds: 1.0 / 24, iso: nil))
    }

    @Test func changedGroupsNamesOnlyWhatDiffers() {
        let base = ManualSettings.automatic
        #expect(base.changedGroups(from: base).isEmpty)
        #expect(base.changedGroups(from: nil) == [.exposure, .whiteBalance, .focus])
        let biased = base.setting(.bias, to: 1, live: live)
        #expect(biased.changedGroups(from: nil) == [.exposure, .bias, .whiteBalance, .focus])
        #expect(biased.changedGroups(from: base) == [.bias])
        let shutter = base.setting(.shutter, to: 0.01, live: live)
        #expect(shutter.changedGroups(from: base) == [.exposure])
        #expect(shutter.setting(.iso, to: 400, live: live).changedGroups(from: shutter) == [.exposure])
        let wb = base.setting(.tint, to: 3, live: live)
        #expect(wb.changedGroups(from: shutter) == [.exposure, .whiteBalance])
        #expect(base.setting(.focus, to: 0.5, live: live).changedGroups(from: base) == [.focus])
        #expect(shutter.changedGroups(from: shutter).isEmpty)
    }
}
