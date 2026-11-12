import Foundation
import Testing
@testable import OpenCam

/// The camera's start sequence over a fake session: from lens discovery to the armed confirmation, with and without a saved start.
@MainActor @Suite struct CameraLaunchTests {
    private static let wide = Lens(id: "W", kind: .wide, deviceUniqueID: "W", zoomFactor: 1, label: "1x")
    private static let descriptor = FormatDescriptor(lensID: "W", width: 1920, height: 1080, isBinned: false, frameRateRanges: [1...30],
                                                     codecTypesByColourSpace: [0: ["hvc1"]], allowsCompressionProperties: true,
                                                     maxPhotoDimensions: [PhotoSize(width: 4032, height: 3024)], hasBayerRAW: false)

    /// Where the capabilities come from on this launch.
    private enum Source {
        /// The fixture, saved under this device's build and model; nothing is scanned.
        case cached
        /// No cache file; one lens with one format is scanned.
        case scanned
        /// No cache file; the scan throws.
        case scanFails
        /// No camera is discovered.
        case noLens
    }

    private struct Rig {
        let model: CameraModel
        let fake: FakeSessionConfigurator
        let defaults: UserDefaults
        let directory: URL
        let hook: ScanHook
        /// What a second model resolves from the same capabilities and defaults.
        let expected: SessionConfiguration
    }

    /// A model with no capabilities, as the device launches it, over a fake session. With `failsConfigure` the resolved lens
    /// cannot be configured.
    private func rig(_ source: Source = .cached, delay: Duration = .milliseconds(40), failsConfigure: Bool = false) throws -> Rig {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let defaults = try Fixture.freshDefaults()
        let hook = ScanHook()
        let lenses: [Lens]
        let capabilities: CaptureCapabilities
        let formats = [Self.descriptor]
        switch source {
        case .cached:
            var fixture = try Fixture.load()
            fixture.osBuild = DeviceIdentity.osBuild(); fixture.modelIdentifier = DeviceIdentity.modelIdentifier()
            try CapabilityCache(directory: directory).save(fixture)
            lenses = fixture.lenses
            capabilities = fixture
        case .scanned, .scanFails, .noLens:
            lenses = source == .noLens ? [] : [Self.wide]
            capabilities = CapabilityMapper.capabilities(lenses: [Self.wide], formats: formats, osBuild: DeviceIdentity.osBuild(),
                                                         modelIdentifier: DeviceIdentity.modelIdentifier())
        }
        let capabilitySource = CapabilitySource(cacheDirectory: directory, documentsDirectory: nil, discoverLenses: { lenses }, scan: { _ throws(CameraSessionError) in
            await hook.run()
            if source == .scanFails { throw .noMatchingFormat(option: "scan") }
            return formats
        })
        // The selection the last run saved, as every launch that can use a saved start has one. A first launch would settle the
        // empty model's placeholder photo selection, not pick the default one, so the two models would not agree.
        let second = CameraModel(config: LaunchConfig(), capabilities: capabilities, isSimulator: false, defaults: defaults)
        second.currentSelection.save(to: defaults)
        let expected = try #require(second.sessionConfiguration)
        let empty = CaptureCapabilities(lenses: [], videoOptions: [], photoOptions: [], osBuild: "", modelIdentifier: "")
        let model = CameraModel(config: LaunchConfig(), capabilities: empty, isSimulator: false, defaults: defaults, capabilitySource: capabilitySource)
        model.confirmationDelay = delay
        let fake = FakeSessionConfigurator(failingLensIDs: failsConfigure ? [expected.lens.id] : [])
        return Rig(model: model, fake: fake, defaults: defaults, directory: directory, hook: hook, expected: expected)
    }

    @Test func aNormalStartConfiguresAttachesStartsAndConfirms() async throws {
        let rig = try rig()
        #expect(await rig.model.startCamera(on: rig.fake, savedStart: nil))
        #expect(await rig.fake.calls == ["configure", "start"])
        #expect(await rig.fake.applied == [rig.expected])
        #expect(rig.model.phase == .ready)
        #expect(rig.model.lastWorking?.configuration == rig.expected)
        #expect(rig.model.requestedConfiguration == rig.expected)
        #expect(rig.model.confirmed == nil)
        #expect(await eventually { rig.model.confirmed?.configuration == rig.expected })
    }

    @Test func aNormalStartWhoseConfigureThrowsFails() async throws {
        let rig = try rig(failsConfigure: true)
        #expect(await !rig.model.startCamera(on: rig.fake, savedStart: nil))
        #expect(rig.model.phase == .failed("This format could not be set up."))
        #expect(rig.model.configurator == nil)
        #expect(await rig.fake.calls.isEmpty)
    }

    @Test func aStartWithoutACacheScansFirst() async throws {
        let rig = try rig(.scanned)
        #expect(await rig.model.startCamera(on: rig.fake, savedStart: nil))
        #expect(await rig.fake.calls == ["configure", "start"])
        #expect(rig.model.phase == .ready)
        #expect(CapabilityCache(directory: rig.directory).load(osBuild: DeviceIdentity.osBuild(), modelIdentifier: DeviceIdentity.modelIdentifier()) != nil)
    }
}
