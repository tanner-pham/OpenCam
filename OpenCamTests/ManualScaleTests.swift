import Foundation
import Testing
@testable import OpenCam

@Suite struct ManualScaleTests {
    private func photoRanges() -> ManualRanges {
        ManualRanges(shutterSeconds: (1.0 / 8000)...(1.0 / 3), iso: 34...6400, bias: -8...8, hasWhiteBalance: true, hasFocus: true)
    }

    private func videoRanges(frame: Double) -> ManualRanges {
        ManualRanges(shutterSeconds: (1.0 / 8000)...frame, iso: 34...6400, bias: -8...8, hasWhiteBalance: true, hasFocus: true, frameSeconds: frame)
    }

    private func scale(_ control: ManualControl, _ ranges: ManualRanges) throws -> ManualScale {
        try #require(ManualScale.make(for: control, ranges: ranges))
    }

    @Test func shutterStopsStayInsideTheFormat() throws {
        let values = try scale(.shutter, photoRanges()).values
        #expect(values == values.sorted())
        #expect(Set(values).count == values.count)
        #expect(values.allSatisfy { ($0 >= 1.0 / 8000) && ($0 <= 1.0 / 3) })
        #expect(values.first == 1.0 / 8000)
        #expect(values.last == 1.0 / 3)
    }

    @Test func aVideoShutterEndsAtTheFrameTime() throws {
        let slow = try scale(.shutter, videoRanges(frame: 1.0 / 24)).values
        #expect(slow.last == 1.0 / 24)
        #expect(slow.contains(1.0 / 48))
        #expect(slow.allSatisfy { $0 <= 1.0 / 24 })
        let fast = try scale(.shutter, videoRanges(frame: 1.0 / 30)).values
        #expect(fast.filter { abs($0 - 1.0 / 30) < 1e-9 }.count == 1)
        #expect(fast.last == 1.0 / 30)
        #expect(fast.contains(1.0 / 60))
    }

    @Test func isoRunsInThirdStopsAndIncludesBothEnds() throws {
        let values = try scale(.iso, photoRanges()).values
        #expect(values.first == 34)
        #expect(values[1] == 40)
        #expect(values.last == 6400)
        #expect(values == values.sorted())
        #expect(values.contains(100) && values.contains(125) && values.contains(1600))
    }

    @Test func evStepsAreThirdsAndIncludeZero() throws {
        let values = try scale(.bias, ManualRanges(bias: -2...2)).values
        #expect(values.count == 13)
        #expect(values.contains(0))
        #expect(abs(values[1] - (-5.0 / 3)) < 1e-9)
        #expect(values.first == -2 && values.last == 2)
    }

    @Test func temperatureStepsBy100K() throws {
        let values = try scale(.temperature, photoRanges()).values
        #expect(values.count == 76)
        #expect(values.first == 2500 && values.last == 10000)
        #expect(values[1] == 2600)
    }

    @Test func tintAndFocusScales() throws {
        let tint = try scale(.tint, photoRanges())
        #expect(tint.values.count == 101 && tint.values.first == -50 && tint.values.last == 50)
        let focus = try scale(.focus, photoRanges())
        #expect(focus.values.count == 101 && focus.values.first == 0 && focus.values.last == 1)
    }

    @Test func aCameraThatCannotSetAControlHasNoScale() {
        let none = ManualRanges()
        for control in ManualControl.allCases {
            #expect(ManualScale.make(for: control, ranges: none) == nil)
        }
    }

    @Test func nearestStepUsesStops() throws {
        let shutter = try scale(.shutter, photoRanges())
        let step = shutter.step(nearest: 1.0 / 97)
        #expect(shutter.values[step] == 1.0 / 100)
        let linear = try scale(.temperature, photoRanges())
        #expect(linear.values[linear.step(nearest: 5640)] == 5600)
        #expect(linear.step(nearest: .nan) == 0)
    }

    @Test func stepsClampToTheScale() throws {
        let tint = try scale(.tint, photoRanges())
        #expect(tint.step(100, movedBy: 5) == 100)
        #expect(tint.step(2, movedBy: -5) == 0)
        #expect(tint.step(50, movedBy: 3) == 53)
    }

    @Test func detents() throws {
        let tint = try scale(.tint, photoRanges())
        #expect(!tint.crossesDetent(from: 52, to: 57))
        #expect(tint.crossesDetent(from: 57, to: 61))
        #expect(tint.crossesDetent(from: 49, to: 51))
        #expect(tint.crossesDetent(from: 61, to: 57))
        let shutter = try scale(.shutter, photoRanges())
        #expect(shutter.crossesDetent(from: 3, to: 4))
        #expect(!shutter.crossesDetent(from: 3, to: 3))
        let focus = try scale(.focus, photoRanges())
        #expect(focus.crossesDetent(from: 24, to: 25))
        #expect(!focus.crossesDetent(from: 26, to: 49))
    }

    @Test func strides() throws {
        let ranges = photoRanges()
        #expect(try scale(.tint, ranges).adjustStride == 5)
        #expect(try scale(.focus, ranges).detentStride == 25)
        #expect(try scale(.shutter, ranges).adjustStride == 1)
        #expect(try scale(.shutter, ranges).isLogarithmic)
        #expect(try !scale(.bias, ranges).isLogarithmic)
    }

    @Test func spokenValues() {
        #expect(ManualControl.shutter.spoken(1.0 / 60) == "1/60 second")
        #expect(ManualControl.shutter.spoken(2.5) == "2.5 seconds")
        #expect(ManualControl.shutter.spoken(1) == "1 second")
        #expect(ManualControl.shutter.spoken(1 / 2.5) == "0.4 seconds")
        #expect(ManualControl.shutter.spoken(0.5) == "0.5 seconds")
        #expect(ManualControl.shutter.spoken(2) == "2 seconds")
        #expect(ManualControl.iso.spoken(400) == "ISO 400")
        #expect(ManualControl.bias.spoken(0.3) == "+0.3 EV")
        #expect(ManualControl.temperature.spoken(5600) == "5600 kelvin")
        #expect(ManualControl.tint.spoken(4) == "Tint +4")
        #expect(ManualControl.focus.spoken(0.85) == "Focus 0.85")
        for control in ManualControl.allCases {
            #expect(control.spoken(nil) == "Not available")
            #expect(control.spoken(.nan) == "Not available")
            #expect(!control.spoken(1).contains("\u{2014}"))
        }
    }

    @Test func textMatchesTheReadouts() {
        #expect(ManualControl.shutter.text(1.0 / 60) == ReadoutFormatter.shutter(1.0 / 60))
        #expect(ManualControl.iso.text(400) == "400")
        #expect(ManualControl.bias.text(nil) == "--")
        #expect(ManualControl.temperature.text(5620) == "5600K")
        #expect(ManualControl.tint.text(-2) == "-2")
        #expect(ManualControl.focus.text(0.5) == "0.50")
    }

    @Test func controlsDescribeThemselves() {
        #expect(ManualControl.allCases.map(\.caption) == ["SHUTTER", "ISO", "EV", "WB", "TINT", "FOCUS"])
        #expect(ManualControl.bias.rawValue == "ev" && ManualControl.temperature.rawValue == "wb")
        #expect(ManualControl.allCases.filter { !$0.hasAutomatic } == [.bias])
        #expect(ManualControl.bias.name == "Exposure bias")
    }
}
