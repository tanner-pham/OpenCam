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
    @Test func theStripShowsTheThreeItemsWhenNoControlIsOpen() throws {
        #expect(StripToolbar.items(open: nil, isLandscape: false) == [.mode, .lens, .library])
        #expect(StripToolbar.items(open: nil, isLandscape: true) == [.library, .lens, .mode])
        // Closing the slider returns them.
        let model = try model()
        model.openControl = .iso
        model.closeControl()
        #expect(StripToolbar.items(open: model.openControl, isLandscape: false) == [.mode, .lens, .library])
    }

    @Test func closingASliderReturnsTheStripToModeLensAndLibrary() throws {
        let model = try model()
        for control in ManualControl.allCases {
            model.toggleControl(control)
            #expect(model.openControl == control)
            #expect(StripToolbar.items(open: model.openControl, isLandscape: false) != [.mode, .lens, .library])
            model.closeControl()
            #expect(model.openControl == nil)
            #expect(StripToolbar.items(open: model.openControl, isLandscape: false) == [.mode, .lens, .library])
            #expect(StripToolbar.items(open: model.openControl, isLandscape: true) == [.library, .lens, .mode])
        }
        // Tapping the open readout again closes it too.
        model.toggleControl(.iso)
        model.toggleControl(.iso)
        #expect(StripToolbar.items(open: model.openControl, isLandscape: false) == [.mode, .lens, .library])
    }

    @Test func anOpenControlSwapsInSliderAutoAndClose() {
        for control in ManualControl.allCases where control != .bias {
            #expect(StripToolbar.items(open: control, isLandscape: false) == [.slider, .auto, .close])
            #expect(StripToolbar.items(open: control, isLandscape: true) == [.close, .auto, .slider])
        }
        // EV has no automatic state, so no Auto.
        #expect(StripToolbar.items(open: .bias, isLandscape: false) == [.slider, .close])
        #expect(StripToolbar.items(open: .bias, isLandscape: true) == [.close, .slider])
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
