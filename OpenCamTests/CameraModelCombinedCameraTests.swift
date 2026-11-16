import Foundation
import Testing
@testable import OpenCam

/// What the model asks the session for when the device has a combined back camera, and how it learns of that camera at launch.
@MainActor @Suite struct CameraModelCombinedCameraTests {
    static let combined = CombinedCamera(
        deviceUniqueID: "fixture-dual", baseZoomByDeviceID: ["fixture-ultraWide": 1, "fixture-wide": 2],
        formats: [3840, 1920].flatMap { width in
            [CombinedFormat(width: width, height: width * 9 / 16, colourSpaces: [0, 1, 2], frameRateRanges: [1...60], maxZoomFactor: 100)]
        })

    private func model(combined: CombinedCamera? = combined, mode: CaptureMode = .video) throws -> CameraModel {
        let model = CameraModel(config: LaunchConfig(), capabilities: try Fixture.load(), isSimulator: false, defaults: try Fixture.freshDefaults(),
                                captureStore: try CaptureStore(directory: TestFiles.directory()))
        model.combinedCamera = combined
        model.mode = mode
        model.phase = .ready
        model.attachSession(FakeSessionConfigurator(failingLensIDs: []), configuredWith: try #require(model.sessionConfiguration),
                            selection: model.currentSelection)
        return model
    }

    @Test func videoOnABackLensNamesTheCombinedCamera() throws {
        let model = try model()
        model.selectLens("wide")
        #expect(model.sessionConfiguration?.combined == CombinedLens(deviceUniqueID: "fixture-dual", zoomFactor: 2))
        model.selectLens("ultraWide")
        #expect(model.sessionConfiguration?.combined == CombinedLens(deviceUniqueID: "fixture-dual", zoomFactor: 1))
        model.selectLens("wide@2")
        #expect(model.sessionConfiguration?.combined == CombinedLens(deviceUniqueID: "fixture-dual", zoomFactor: 4))
    }

    @Test func photoModeAndFrontLensesKeepTheirOwnCamera() throws {
        let model = try model(mode: .photo)
        #expect(model.sessionConfiguration?.combined == nil)
        model.mode = .video
        model.selectLens("outer")
        #expect(model.sessionConfiguration?.combined == nil)
    }

    @Test func noCombinedCameraChangesNothing() throws {
        let model = try model(combined: nil)
        model.selectLens("wide")
        #expect(model.sessionConfiguration?.combined == nil)
    }

    @Test func aSourceWithACombinedCameraHandsItToTheModel() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        var fixture = try Fixture.load()
        fixture.osBuild = DeviceIdentity.osBuild(); fixture.modelIdentifier = DeviceIdentity.modelIdentifier()
        try CapabilityCache(directory: directory).save(fixture)
        let lenses = fixture.lenses, combined = Self.combined
        let source = CapabilitySource(cacheDirectory: directory, documentsDirectory: nil, discoverLenses: { lenses },
                                      scan: { _ throws(CameraSessionError) in [] },
                                      combinedCamera: { combined })
        let empty = CaptureCapabilities(lenses: [], videoOptions: [], photoOptions: [], osBuild: "", modelIdentifier: "")
        let model = CameraModel(config: LaunchConfig(), capabilities: empty, isSimulator: false, defaults: try Fixture.freshDefaults(),
                                capabilitySource: source)
        model.mode = .video
        let fake = FakeSessionConfigurator(failingLensIDs: [])
        #expect(await model.startCamera(on: fake, savedStart: nil))
        #expect(model.combinedCamera == Self.combined)
        #expect(await fake.applied.first?.combined != nil)
    }
}
