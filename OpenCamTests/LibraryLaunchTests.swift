import Foundation
import Testing
@testable import OpenCam

@MainActor @Suite struct LibraryLaunchTests {
    func model(_ args: [String]) throws -> CameraModel {
        CameraModel(config: .parse(["app"] + args), capabilities: try Fixture.load(), isSimulator: true, defaults: try Fixture.freshDefaults())
    }
    @Test func libraryScreensOpenTheLibrary() throws {
        #expect(try model(["-screen", "library"]).isLibraryPresented); #expect(try model(["-screen", "editor"]).isLibraryPresented)
        #expect(try model(["-screen", "library"]).sheet == nil); #expect(!(try model(["-screen", "record"]).isLibraryPresented))
    }
    @Test func libraryDoesNotOpenWhileRecording() throws {
        let recording = try model(["-recording", "on"]); recording.openLibrary(); #expect(!recording.isLibraryPresented)
        let idle = try model([]); idle.openLibrary(); #expect(idle.isLibraryPresented)
    }
    @Test func cameraUsesTheInjectedCaptureStore() throws {
        let dir = try TestFiles.directory()
        try Data("x".utf8).write(to: dir.appending(path: "OC_0007.HEIC"))
        let store = try CaptureStore(directory: dir)
        let model = CameraModel(config: LaunchConfig(), capabilities: try Fixture.load(), isSimulator: true, defaults: try Fixture.freshDefaults(), captureStore: store)
        model.loadLastCapture()
        #expect(model.lastCapture.map(CaptureStore.clipKey(for:)) == "OC_0007.HEIC")
        #expect(model.store(failureNotice: "x") === store)
    }
}
