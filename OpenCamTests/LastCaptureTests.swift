import Foundation
import Testing
@testable import OpenCam

@MainActor @Suite struct LastCaptureTests {
    @Test func refreshDropsADeletedLastCapture() throws {
        let dir = try TestFiles.directory()
        try Data("x".utf8).write(to: dir.appending(path: "OC_0001.HEIC")); try Data("x".utf8).write(to: dir.appending(path: "OC_0002.JPG"))
        let model = CameraModel(config: LaunchConfig(), capabilities: try Fixture.load(), isSimulator: true, defaults: try Fixture.freshDefaults(),
                                captureStore: try CaptureStore(directory: dir))
        model.loadLastCapture(); #expect(model.lastCapture.map(CaptureStore.clipKey(for:)) == "OC_0002.JPG")
        try FileManager.default.removeItem(at: dir.appending(path: "OC_0002.JPG"))
        model.refreshLastCapture(); #expect(model.lastCapture.map(CaptureStore.clipKey(for:)) == "OC_0001.HEIC")
        model.openLibrary(); #expect(model.isLibraryPresented)
    }

    @Test func latestCaptureCountsImportsAndSamples() {
        #expect(CaptureStore.latestCaptureName(["OC_0003.HEIC", "OC_0004.JPG", "OC_0005.json", "OC_0005.edit.json"]) == "OC_0004.JPG")
        #expect(CaptureStore.latestCaptureName(["OC_0006.DNG", "OC_0006.HEIC", "OC_0002.PNG"]) == "OC_0006.HEIC")
        #expect(CaptureStore.nextSequence(existingNames: ["OC_0003.HEIC", "OC_0009.edit.json", "IMG_7.JPG", "OC_.json"]) == 10)   // one shared parser
    }

    /// The Library covers the camera, so it opens only when the strip's Lens and Mode items could change.
    @Test func libraryStaysClosedWhileFormatsAreScannedOrSwept() throws {
        let model = CameraModel(config: LaunchConfig(), capabilities: try Fixture.load(), isSimulator: true, defaults: try Fixture.freshDefaults(),
                                captureStore: try CaptureStore(directory: TestFiles.directory()))
        model.isScanningFormats = true
        #expect(!model.canOpenLibrary); model.openLibrary(); #expect(!model.isLibraryPresented)
        model.isScanningFormats = false
        model.isSweeping = true
        #expect(!model.canOpenLibrary); model.openLibrary(); #expect(!model.isLibraryPresented)
        model.isSweeping = false
        #expect(model.canOpenLibrary)
    }
}
