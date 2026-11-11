import Foundation
import Testing
@testable import OpenCam

/// The strip holds Mode, Lens and Library; Mode is a toggle between the two capture modes.
@MainActor @Suite struct StripItemsTests {
    func model() throws -> CameraModel {
        CameraModel(config: LaunchConfig(), capabilities: try Fixture.load(), isSimulator: true, defaults: try Fixture.freshDefaults(),
                    captureStore: try CaptureStore(directory: TestFiles.directory()))
    }

    /// The format button opens Record settings, so the strip no longer offers it.
    @Test func recordSettingsIsNoLongerAStripItem() {
        #expect(StripToolbar.Item.allCases == [.mode, .lens, .library])
    }

    @Test func theModeToggleSwitchesBetweenTheTwoModes() throws {
        let model = try model()
        #expect(model.mode == .video)
        let record = model.record, photo = model.photo
        model.toggleMode()
        #expect(model.mode == .photo); #expect(model.photo == photo); #expect(model.record == record)
        model.toggleMode()
        #expect(model.mode == .video); #expect(model.record == record); #expect(model.photo == photo)
    }

    @Test func theModeToggleIsRefusedWhileModeCannotChange() throws {
        let model = try model()
        model.isRecording = true
        model.toggleMode(); #expect(model.mode == .video)
        model.isRecording = false
        model.isSweeping = true
        model.toggleMode(); #expect(model.mode == .video)
        model.isSweeping = false
        model.isScanningFormats = true
        model.toggleMode(); #expect(model.mode == .video)
        model.isScanningFormats = false
        model.toggleMode(); #expect(model.mode == .photo)
    }
}
