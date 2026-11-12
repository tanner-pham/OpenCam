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

    // MARK: A saved start

    private static let stop = "[CameraSession:runtimeError] Session stopped — {domain: AVFoundationErrorDomain, code: -11800, The operation could not be completed}"

    /// A field of the configuration a saved start can disagree about.
    enum Field: CaseIterable {
        case mode, lens, video, photo, includesAudio, needsFrames

        func changing(_ configuration: SessionConfiguration) -> SessionConfiguration {
            var changed = configuration
            switch self {
            case .mode: changed.mode = configuration.mode == .video ? .photo : .video
            case .lens: changed.lens = Lens(id: "other", kind: .wide, deviceUniqueID: "other", zoomFactor: 1, label: "1x")
            case .video: changed.video = nil
            case .photo: changed.photo = nil
            case .includesAudio: changed.includesAudio.toggle()
            case .needsFrames: changed.needsFrames.toggle()
            }
            return changed
        }
    }

    @Test func aSavedStartThatMatchesIsAdoptedWithoutAConfigure() async throws {
        let rig = try rig()
        let expected = rig.expected
        #expect(await rig.model.startCamera(on: rig.fake, savedStart: Task { expected }))
        #expect(await rig.fake.calls == ["start"])
        #expect(await rig.fake.applied.isEmpty)
        #expect(rig.model.lastWorking?.configuration == expected)
        #expect(rig.model.lastWorking?.selection == rig.model.currentSelection)
        #expect(rig.model.requestedConfiguration == expected)
        #expect(rig.model.phase == .ready)
        #expect(rig.model.notice == nil)
    }

    @Test func aSavedStartIsConfirmedOnlyAfterTheDelay() async throws {
        let rig = try rig(delay: .milliseconds(300))
        let expected = rig.expected
        #expect(SavedStart.load(from: rig.defaults) == nil)
        #expect(await rig.model.startCamera(on: rig.fake, savedStart: Task { expected }))
        #expect(rig.model.confirmed == nil)
        #expect(SavedStart.load(from: rig.defaults) == nil)
        #expect(await eventually { rig.model.confirmed?.configuration == expected })
        #expect(SavedStart.load(from: rig.defaults)?.configuration == expected)
    }

    @Test func aStopRightAfterASavedStartRecoversLikeANormalStart() async throws {
        let rig = try rig(delay: .milliseconds(300))
        let expected = rig.expected
        #expect(await rig.model.startCamera(on: rig.fake, savedStart: Task { expected }))
        let selection = rig.model.currentSelection
        rig.model.apply(.runtimeError(Self.stop))
        await rig.model.waitForQueuedConfigures()
        #expect(await rig.fake.calls == ["start", "configure", "start"])
        #expect(await rig.fake.applied == [expected])
        #expect(rig.model.currentSelection == selection)
        #expect(rig.model.notice == nil)
        #expect(await eventually { rig.model.phase == .ready })
        #expect(await eventually { rig.model.confirmed?.configuration == expected })
    }

    @Test(arguments: Field.allCases) func aSavedStartThatDiffersIsDiscardedNotPatched(field: Field) async throws {
        let rig = try rig()
        let differing = field.changing(rig.expected)
        #expect(differing != rig.expected)
        #expect(await rig.model.startCamera(on: rig.fake, savedStart: Task { differing }))
        #expect(await rig.fake.calls == ["release", "configure", "start"])
        #expect(await rig.fake.applied == [rig.expected])
        #expect(rig.model.phase == .ready)
        #expect(rig.model.notice == nil)
    }

    @Test func aSavedStartThatCouldNotBeConfiguredIsSilent() async throws {
        let rig = try rig()
        let before = SavedSelections.load(from: rig.defaults)
        #expect(before != nil)
        #expect(await rig.model.startCamera(on: rig.fake, savedStart: Task { nil }))
        #expect(await rig.fake.calls == ["release", "configure", "start"])
        #expect(await rig.fake.applied == [rig.expected])
        #expect(rig.model.notice == nil)
        #expect(rig.model.phase == .ready)
        #expect(SavedSelections.load(from: rig.defaults) == before)
    }

    @Test func aSavedStartIsReleasedBeforeTheScan() async throws {
        let rig = try rig(.scanned)
        let expected = rig.expected
        var ranDuringScan = true, heldCameraDuringScan = true
        let fake = rig.fake
        rig.hook.action = {
            ranDuringScan = await fake.isRunning
            heldCameraDuringScan = await fake.holdsCamera
        }
        #expect(await rig.model.startCamera(on: fake, savedStart: Task { expected }))
        #expect(!ranDuringScan); #expect(!heldCameraDuringScan)
        #expect(await fake.calls == ["release", "configure", "start"])
    }

    /// Ways the start can fail once a saved start began.
    enum Failure: CaseIterable {
        case noLens, scanThrows, configureThrows

        var phase: CameraPhase {
            switch self {
            case .noLens, .scanThrows: .failed("The camera could not start.")
            case .configureThrows: .failed("This format could not be set up.")
            }
        }
    }

    @Test(arguments: Failure.allCases) func aStartThatFailsAfterASavedStartLeavesNoCameraRunning(failure: Failure) async throws {
        let rig: Rig
        switch failure {
        case .noLens: rig = try self.rig(.noLens)
        case .scanThrows: rig = try self.rig(.scanFails)
        case .configureThrows: rig = try self.rig(failsConfigure: true)
        }
        let saved = failure == .configureThrows ? Field.mode.changing(rig.expected) : rig.expected
        #expect(await !rig.model.startCamera(on: rig.fake, savedStart: Task { saved }))
        #expect(await rig.fake.calls == ["release"])
        #expect(await !rig.fake.isRunning); #expect(await !rig.fake.holdsCamera)
        #expect(rig.model.phase == failure.phase)
        #expect(rig.model.configurator == nil)
    }

    @Test func aScriptedLaunchNeverStartsFromTheRecord() throws {
        let defaults = try Fixture.freshDefaults()
        let capabilities = try Fixture.load()
        let first = CameraModel(config: LaunchConfig(), capabilities: capabilities, isSimulator: false, defaults: defaults)
        first.currentSelection.save(to: defaults)
        var configuration = try #require(first.sessionConfiguration)
        configuration.includesAudio = true
        SavedStart(configuration: configuration, record: first.record, photo: first.photo, osBuild: DeviceIdentity.osBuild(),
                   modelIdentifier: DeviceIdentity.modelIdentifier(), scanVersion: CaptureCapabilities.currentScanVersion).save(to: defaults)
        let access = CaptureAccess(camera: .authorized, microphone: .authorized)

        let scripted = CameraModel(config: LaunchConfig.parse(["-mode", "video"]), capabilities: capabilities, isSimulator: false, defaults: defaults)
        #expect(scripted.savedStartConfiguration(access: access) == nil)
        let normal = CameraModel(config: LaunchConfig(), capabilities: capabilities, isSimulator: false, defaults: defaults)
        #expect(normal.savedStartConfiguration(access: access) == configuration)
    }

    @Test func aSavedStartForAMissingCameraIsNil() async throws {
        let rig = try rig()
        #expect(await CameraSession().startSaved(rig.expected).value == nil)
    }

    @Test func eventsFromAReleasedSavedStartAreIgnored() async throws {
        let rig = try rig(delay: .milliseconds(300))
        let differing = Field.mode.changing(rig.expected)
        #expect(await rig.model.startCamera(on: rig.fake, savedStart: Task { differing }))
        let selection = rig.model.currentSelection
        let saved = SavedSelections.load(from: rig.defaults)
        let errors = rig.model.runtimeErrorCount

        rig.model.apply(.runtimeError("stale"))
        #expect(rig.model.notice == nil)
        #expect(rig.model.currentSelection == selection)
        #expect(SavedSelections.load(from: rig.defaults) == saved)
        #expect(rig.model.runtimeErrorCount == errors)
        #expect(rig.model.phase == .ready)
        #expect(await rig.fake.calls == ["release", "configure", "start"])

        rig.model.apply(.savedStartReleased)
        rig.model.apply(.runtimeError(Self.stop))
        #expect(rig.model.runtimeErrorCount == errors + 1)
        await rig.model.waitForQueuedConfigures()
        #expect(await rig.fake.calls == ["release", "configure", "start", "configure", "start"])
        #expect(await rig.fake.applied == [rig.expected, rig.expected])
        #expect(rig.model.currentSelection == selection)
        #expect(rig.model.notice == nil)
        #expect(await eventually { rig.model.phase == .ready })
    }

    @Test func eventsFromAnAdoptedSavedStartAreApplied() async throws {
        let rig = try rig(delay: .milliseconds(300))
        let expected = rig.expected
        #expect(await rig.model.startCamera(on: rig.fake, savedStart: Task { expected }))
        #expect(!rig.model.isIgnoringEventsUntilSavedStartReleased)
        rig.model.apply(.runtimeError(Self.stop))
        #expect(rig.model.runtimeErrorCount == 1)
        await rig.model.waitForQueuedConfigures()
        #expect(await rig.fake.calls == ["start", "configure", "start"])
    }
}
