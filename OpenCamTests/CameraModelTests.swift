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

    @Test func nothingNamesAFormatBeforeTheScanHasProducedIt() throws {
        let scanning = CameraModel(config: .parse(["app", "-state", "scanning"]), capabilities: try Fixture.load(), isSimulator: true, defaults: try Fixture.freshDefaults())
        #expect(scanning.phase == .scanning)
        #expect(scanning.summaryParts == ["--"]); #expect(scanning.frameRateText == "--"); #expect(scanning.remainingText == "-- min")
        #expect(!scanning.canOpenRecordSettings)

        let empty = CaptureCapabilities(lenses: [], videoOptions: [], photoOptions: [], osBuild: "", modelIdentifier: "")
        let device = CameraModel(config: LaunchConfig(), capabilities: empty, isSimulator: false, defaults: try Fixture.freshDefaults())
        device.phase = .ready
        #expect(device.summaryParts == ["--"]); #expect(device.frameRateText == "--"); #expect(!device.canOpenRecordSettings)

        let simulator = CameraModel(config: LaunchConfig(), capabilities: try Fixture.load(), isSimulator: true, defaults: try Fixture.freshDefaults())
        #expect(simulator.summaryParts != ["--"]); #expect(simulator.frameRateText == "30"); #expect(simulator.canOpenRecordSettings)
    }

    @Test func noCameraNamesNothingAndMetersReadEmpty() throws {
        for phase in [CameraPhase.cameraDenied, .cameraRestricted, .failed("The camera stopped."), .scanning] {
            let model = CameraModel(config: LaunchConfig(), capabilities: try Fixture.load(), isSimulator: true, defaults: try Fixture.freshDefaults())
            model.phase = phase
            #expect(model.summaryParts == ["--"]); #expect(model.frameRateText == "--"); #expect(model.remainingText == "-- min")
            #expect(!model.canOpenRecordSettings); #expect(!model.canCapture); #expect(model.shownMeterLevels == [0, 0])
        }
        let simulator = CameraModel(config: LaunchConfig(), capabilities: try Fixture.load(), isSimulator: true, defaults: try Fixture.freshDefaults())
        #expect(simulator.shownMeterLevels == [0, 0]); #expect(simulator.remainingText == "677 min")
        let denied = CameraModel(config: .parse(["app", "-state", "micDenied"]), capabilities: try Fixture.load(), isSimulator: true, defaults: try Fixture.freshDefaults())
        denied.phase = .ready
        #expect(denied.shownMeterLevels == [0, 0])
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

    @Test func photoModeHidesVideoReadouts() throws {
        let model = CameraModel(config: .parse(["app", "-mode", "video"]), capabilities: try Fixture.load(), isSimulator: true, defaults: try Fixture.freshDefaults())
        #expect(model.showsVideoReadouts)
        model.mode = .photo
        #expect(!model.showsVideoReadouts)
    }
}
