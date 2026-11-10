import Foundation
import Synchronization
import Testing
@testable import OpenCam

@MainActor @Suite struct CapabilityRescanTests {
    let wide = Lens(id: "W", kind: .wide, deviceUniqueID: "W", zoomFactor: 1, label: "1x")
    let front = Lens(id: "F", kind: .outerUltraWide, deviceUniqueID: "F", zoomFactor: 1, label: "Front")
    let descriptor = FormatDescriptor(lensID: "W", width: 1920, height: 1080, isBinned: false, frameRateRanges: [1...30], codecTypesByColourSpace: [0: ["hvc1"]],
                                      allowsCompressionProperties: true, maxPhotoDimensions: [PhotoSize(width: 4032, height: 3024)], hasBayerRAW: false)

    func source(_ directory: URL) -> CapabilitySource {
        let lenses = [wide, front], formats = [descriptor]
        return CapabilitySource(cacheDirectory: directory, documentsDirectory: nil, discoverLenses: { lenses }, scan: { _ in formats })
    }

    @Test func skippedCameraNoticeCountsCameras() {
        #expect(CameraModel.skippedCamerasNotice(count: 0) == nil)
        #expect(CameraModel.skippedCamerasNotice(count: 1) == "1 camera could not be read.")
        #expect(CameraModel.skippedCamerasNotice(count: 2) == "2 cameras could not be read.")
    }

    @Test func rescanClearsTheCacheAndReplacesCapabilities() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        var stale = try Fixture.load(); stale.osBuild = DeviceIdentity.osBuild(); stale.modelIdentifier = DeviceIdentity.modelIdentifier()
        try CapabilityCache(directory: directory).save(stale)
        let model = CameraModel(config: LaunchConfig(), capabilities: stale, isSimulator: false, defaults: try Fixture.freshDefaults(),
                                capabilitySource: source(directory))
        model.phase = .ready
        let fake = FakeSessionConfigurator(failingLensIDs: [])
        model.attachSession(fake, configuredWith: try #require(model.sessionConfiguration), selection: model.currentSelection)
        #expect(model.canRescanCapabilities)

        await model.rescanCapabilities()
        #expect(model.capabilities.lenses.map(\.id) == ["W"]); #expect(model.capabilities.skippedLensIDs == ["F"])
        #expect(model.lensID == "W"); #expect(model.phase == .ready); #expect(model.notice == "1 camera could not be read.")
        let cached = try #require(CapabilityCache(directory: directory).load(osBuild: stale.osBuild, modelIdentifier: stale.modelIdentifier))
        #expect(cached == model.capabilities)
        #expect(await fake.stopCount == 1); #expect(await fake.isRunning); #expect(await fake.applied.last?.lens.id == "W")
    }

    @Test func aWorkingRescanClearsTheEarlierScanNotice() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let discovered = Mutex([wide, front]), formats = [descriptor]
        let changing = CapabilitySource(cacheDirectory: directory, documentsDirectory: nil, discoverLenses: { discovered.withLock { $0 } }, scan: { _ in formats })
        let model = CameraModel(config: LaunchConfig(), capabilities: try Fixture.load(), isSimulator: false, defaults: try Fixture.freshDefaults(),
                                capabilitySource: changing)
        model.phase = .ready
        model.attachSession(FakeSessionConfigurator(failingLensIDs: []), configuredWith: try #require(model.sessionConfiguration), selection: model.currentSelection)
        await model.rescanCapabilities()
        #expect(model.notice == "1 camera could not be read.")

        discovered.withLock { $0 = [wide] }
        await model.rescanCapabilities()
        #expect(model.notice == nil)
    }

    @Test func lensChangeDuringARescanIsConfiguredOnceAfterTheScan() async throws {
        let tele = Lens(id: "W@2", kind: .wide, deviceUniqueID: "W", zoomFactor: 2, label: "2x")
        let lenses = [wide, tele], formats = [descriptor]
        let hook = ScanHook()
        let source = CapabilitySource(cacheDirectory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString), documentsDirectory: nil,
                                      discoverLenses: { lenses }, scan: { _ in await hook.run(); return formats })
        let caps = CapabilityMapper.capabilities(lenses: lenses, formats: formats, osBuild: "B", modelIdentifier: "M")
        let model = CameraModel(config: LaunchConfig(), capabilities: caps, isSimulator: false, defaults: try Fixture.freshDefaults(), capabilitySource: source)
        model.phase = .ready
        let fake = FakeSessionConfigurator(failingLensIDs: [])
        model.attachSession(fake, configuredWith: try #require(model.sessionConfiguration), selection: model.currentSelection)
        #expect(model.lensID == "W"); #expect(model.canChangeLensOrMode)

        var appliedDuringScan: [SessionConfiguration] = [], couldChangeDuringScan = true
        hook.action = {
            couldChangeDuringScan = model.canChangeLensOrMode
            model.selectLens("W@2")
            await model.waitForQueuedConfigures()
            appliedDuringScan = await fake.applied
        }
        await model.rescanCapabilities()

        #expect(!couldChangeDuringScan); #expect(appliedDuringScan.isEmpty)
        #expect(model.lensID == "W@2"); #expect(model.canChangeLensOrMode)
        #expect(await fake.applied.map(\.lens.id) == ["W@2"])
    }

    @Test func rescanIsAvailableOnlyWithARunningCamera() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let model = CameraModel(config: LaunchConfig(), capabilities: try Fixture.load(), isSimulator: false, defaults: try Fixture.freshDefaults(),
                                capabilitySource: source(directory))
        for phase in [CameraPhase.failed("The camera stopped."), .cameraDenied, .cameraRestricted, .scanning, .simulator] {
            model.phase = phase
            #expect(!model.canRescanCapabilities)
        }
        model.phase = .failed("The camera stopped.")
        await model.rescanCapabilities()
        #expect(model.capabilities == (try Fixture.load())); #expect(model.phase == .failed("The camera stopped."))
        model.phase = .ready
        #expect(model.canRescanCapabilities)
    }

    @Test func rescanIsUnavailableWhileRecording() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let model = CameraModel(config: .parse(["app", "-recording", "on"]), capabilities: try Fixture.load(), isSimulator: false,
                                defaults: try Fixture.freshDefaults(), capabilitySource: source(directory))
        model.phase = .ready
        #expect(!model.canRescanCapabilities)
        await model.rescanCapabilities()
        #expect(model.capabilities == (try Fixture.load()))
    }
}
