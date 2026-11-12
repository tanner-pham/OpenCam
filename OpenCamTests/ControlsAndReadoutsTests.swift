import AVKit
import Foundation
import Testing
@testable import OpenCam

@Suite struct ControlsAndReadoutsTests {
    @Test func onlyEndedPhaseActs() {
        #expect(CaptureAction.forEvent(phase: .began, mode: .photo, isRecording: false) == nil)
        #expect(CaptureAction.forEvent(phase: .cancelled, mode: .video, isRecording: true) == nil)
        #expect(CaptureAction.forEvent(phase: .ended, mode: .photo, isRecording: false) == .takePhoto)
        #expect(CaptureAction.forEvent(phase: .ended, mode: .video, isRecording: false) == .startRecording)
        #expect(CaptureAction.forEvent(phase: .ended, mode: .video, isRecording: true) == .stopRecording)
    }
    @Test func controlPlan() {
        #expect(CameraControlPlan.kinds(supportsControls: false, mode: .video, photoFormat: .heif) == [])
        #expect(CameraControlPlan.kinds(supportsControls: true, mode: .video, photoFormat: .raw) == [.zoom, .exposureBias])
        #expect(CameraControlPlan.kinds(supportsControls: true, mode: .photo, photoFormat: .rawPlusHEIF) == [.exposureBias])
        #expect(CameraControlPlan.kinds(supportsControls: true, mode: .photo, photoFormat: .heif) == [.zoom, .exposureBias])
        #expect(CameraControlPlan.enablesExposureBias(for: .automatic))
        #expect(!CameraControlPlan.enablesExposureBias(for: .manual(shutterSeconds: nil, iso: 400)))
    }
    @Test func shutterReadsAsAFractionBelowThirtyFiveHundredthsOfASecondAndSecondsFromThere() {
        #expect(ReadoutFormatter.shutter(1.0 / 4) == "1/4")
        #expect(ReadoutFormatter.shutter(1.0 / 3) == "1/3")
        #expect(ReadoutFormatter.shutter(0.35) == "0.4s")
        #expect(ReadoutFormatter.shutter(1 / 2.5) == "0.4s")
        #expect(ReadoutFormatter.shutter(1 / 2.0) == "0.5s")
        #expect(ReadoutFormatter.shutter(1 / 1.6) == "0.6s")
        #expect(ReadoutFormatter.shutter(1 / 1.3) == "0.8s")
        #expect(ReadoutFormatter.shutter(1) == "1s")
        #expect(ReadoutFormatter.shutter(2.5) == "2.5s")
    }

    @Test func everyShutterOnThePhotoScaleReadsDifferently() throws {
        let ranges = ManualRanges(shutterSeconds: (1.0 / 8000)...1, iso: 25...3200)
        let scale = try #require(ManualScale.make(for: .shutter, ranges: ranges))
        let texts = scale.values.map { ReadoutFormatter.shutter($0) }
        #expect(Set(texts).count == texts.count, "\(texts)")
        #expect(texts.suffix(7) == ["1/4", "1/3", "0.4s", "0.5s", "0.6s", "0.8s", "1s"])
    }

    @Test func formatting() {
        #expect(ReadoutFormatter.shutter(1.0 / 60) == "1/60"); #expect(ReadoutFormatter.shutter(0.5) == "0.5s"); #expect(ReadoutFormatter.shutter(2.5) == "2.5s")
        #expect(ReadoutFormatter.shutter(nil) == "--"); #expect(ReadoutFormatter.iso(400.4) == "400")
        #expect(ReadoutFormatter.kelvin(5612) == "5600K"); #expect(ReadoutFormatter.kelvin(5630) == "5650K")
        #expect(ReadoutFormatter.tint(3.6) == "+4"); #expect(ReadoutFormatter.tint(-2.2) == "-2"); #expect(ReadoutFormatter.tint(0.3) == "0")
        #expect(ReadoutFormatter.bias(0) == "0.0"); #expect(ReadoutFormatter.bias(0.333) == "+0.3")
        #expect(ReadoutFormatter.focus(0.4213) == "0.42"); #expect(ReadoutFormatter.focus(1) == "1.00"); #expect(ReadoutFormatter.focus(nil) == "--")
        #expect(Timecode.string(elapsed: 42.5, frameRate: 30) == "00:00:42:15"); #expect(Timecode.string(elapsed: 3661, frameRate: 24) == "01:01:01:00")
    }
    @MainActor @Test func withoutACameraReadoutsReadPlaceholdersAndPressesDoNothing() throws {
        let model = CameraModel(config: .parse(["app", "-mode", "video"]), capabilities: try Fixture.load(), isSimulator: true, defaults: try Fixture.freshDefaults())
        #expect(model.frameRateText == "30")
        // The Simulator shows simulated values; only a launch with no camera reads placeholders.
        #expect(ManualControl.allCases.allSatisfy { model.readout(for: $0).text != "--" })
        let scanning = CameraModel(config: .parse(["app", "-state", "scanning"]), capabilities: try Fixture.load(), isSimulator: true, defaults: try Fixture.freshDefaults())
        #expect(ManualControl.allCases.map { scanning.readout(for: $0).text } == Array(repeating: "--", count: 6))
        model.handleCaptureEvent(phase: .ended)
        #expect(!model.isRecording)
    }
    @MainActor @Test func timecodeCountsAtTheRateTheFPSReadoutShows() throws {
        let model = CameraModel(config: .parse(["app", "-mode", "video"]), capabilities: try Fixture.load(), isSimulator: true, defaults: try Fixture.freshDefaults())
        model.record.frameRate = 24
        #expect(model.frameRateText == "24"); #expect(model.timecodeFrameRate == 24)
        let scanning = CameraModel(config: .parse(["app", "-state", "scanning"]), capabilities: try Fixture.load(), isSimulator: true, defaults: try Fixture.freshDefaults())
        #expect(scanning.frameRateText == "--"); #expect(scanning.timecodeFrameRate == 30)
    }
}
