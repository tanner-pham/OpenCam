import Foundation
import Testing
@testable import OpenCam

@MainActor @Suite struct CameraModelTests {
    @Test func selectingALensSettlesTheRecordSelection() throws {
        let model = CameraModel(config: LaunchConfig(), capabilities: try Fixture.load(), isSimulator: true, defaults: try Fixture.freshDefaults())
        model.record = RecordSelection(family: .proRes, quality: "422 HQ", resolution: .named(width: 3840, height: 2160), frameRate: 30, colour: .appleLog2)
        model.selectLens("ultraWide")
        #expect(model.record.resolution.label == "1080p"); #expect(model.summaryParts == ["ProRes", "1080p", "Log 2"])
        model.selectLens("nope"); #expect(model.lensID == "ultraWide")
    }

    @Test func simulatorPhaseAndLaunchState() throws {
        let model = CameraModel(config: .parse(["app", "-mode", "photo", "-recording", "on"]), capabilities: try Fixture.load(), isSimulator: true, defaults: try Fixture.freshDefaults())
        #expect(model.phase == .simulator); #expect(!model.canCapture)
        #expect(model.summaryParts == ["RAW + HEIF", "48 MP"]); #expect(model.isRecording && model.recordingStart != nil)
        #expect(model.freeBytes == 141_000_000_000); #expect(model.sheet == nil)
    }

    @Test func launchScreenOpensItsSheet() throws {
        let caps = try Fixture.load()
        #expect(CameraModel(config: .parse(["app", "-screen", "record"]), capabilities: caps, isSimulator: true, defaults: try Fixture.freshDefaults()).sheet == .record)
        #expect(CameraModel(config: .parse(["app", "-screen", "sweep"]), capabilities: caps, isSimulator: true, defaults: try Fixture.freshDefaults()).sheet == .sweep)
    }

    @Test func defaultLensIsTheUnitZoomWideLens() throws {
        var caps = try Fixture.load()
        caps.lenses = caps.lenses.map { Lens(id: "dev-\($0.id)", kind: $0.kind, deviceUniqueID: $0.deviceUniqueID, zoomFactor: $0.zoomFactor, label: $0.label) }
        let model = CameraModel(config: LaunchConfig(), capabilities: caps, isSimulator: true, defaults: try Fixture.freshDefaults())
        #expect(model.currentLens?.kind == .wide); #expect(model.currentLens?.zoomFactor == 1)
    }

    @Test func lensWithNoOptionsKeepsTheSelectionAndBlocksCapture() throws {
        var caps = try Fixture.load()
        caps.lenses.append(Lens(id: "bare", kind: .innerUltraWide, deviceUniqueID: "bare", zoomFactor: 1, label: "Bare"))
        let model = CameraModel(config: LaunchConfig(), capabilities: caps, isSimulator: true, defaults: try Fixture.freshDefaults())
        let before = model.record
        model.selectLens("bare")
        #expect(model.lensID == "bare"); #expect(model.record == before)
        #expect(model.currentVideoOption == nil); #expect(!model.canCapture)
    }
}
