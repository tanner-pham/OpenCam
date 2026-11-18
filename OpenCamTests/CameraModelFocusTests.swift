import CoreGraphics
import Foundation
import Testing
@testable import OpenCam

/// Tap and hold in the viewfinder, through the model and a fake session. The preview view does not exist in a test, so the
/// device model is given a geometry that fills the view.
@MainActor @Suite struct CameraModelFocusTests {
    static let size = CGSize(width: 400, height: 400)
    static let ranges = ManualRanges(shutterSeconds: (1.0 / 8000)...(1.0 / 3), iso: 25...3200, bias: -2...2, hasWhiteBalance: true, hasFocus: true)

    struct Rig {
        let model: CameraModel
        let fake: FakeSessionConfigurator
    }

    func rig(mode: CaptureMode = .photo) async throws -> Rig {
        let fake = FakeSessionConfigurator(failingLensIDs: [])
        await fake.setRanges(Self.ranges)
        await fake.setReadouts(LiveReadouts(iso: 400, shutterSeconds: 1.0 / 60, kelvin: 5000, tint: 12, exposureBias: 0, lensPosition: 0.5))
        let source = CapabilitySource(cacheDirectory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString),
                                      documentsDirectory: nil, discoverLenses: { [] }, scan: { _ in [] })
        let model = CameraModel(config: LaunchConfig(), capabilities: try Fixture.load(), isSimulator: false, defaults: try Fixture.freshDefaults(),
                                capabilitySource: source, captureStore: try CaptureStore(directory: TestFiles.directory()))
        model.mode = mode
        model.phase = .ready
        model.viewfinderSettle = .milliseconds(20)
        model.focusGeometry = { .filling($0) }
        model.attachSession(fake, configuredWith: try #require(model.sessionConfiguration), selection: model.currentSelection)
        await model.refreshReadouts(from: fake)
        return Rig(model: model, fake: fake)
    }

    func until(_ condition: () async -> Bool) async -> Bool {
        for _ in 0..<200 {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return await condition()
    }

    func focusCount(_ fake: FakeSessionConfigurator) async -> Int {
        await fake.calls.filter { $0 == "focus" }.count
    }

    @Test func withoutAGestureTheSessionHearsNothingNew() async throws {
        let rig = try await rig()
        rig.model.selectLens("ultraWide")
        await rig.model.waitForQueuedConfigures()
        rig.model.toggleControl(.iso)
        rig.model.setControl(.iso, step: 5)
        await rig.model.manualApplyTask?.value
        let calls = await rig.fake.calls
        #expect(!calls.contains("focus")); #expect(!calls.contains("zoom"))
        #expect(await rig.fake.focusRequests.isEmpty)
        #expect(rig.model.focusTap.marker == nil)
    }

    @Test func aTapReachesTheSessionOnce() async throws {
        let rig = try await rig()
        rig.model.focusTapped(at: CGPoint(x: 100, y: 300), in: Self.size)
        #expect(await eventually { rig.model.focusRequests.isIdle })
        let requests = await rig.fake.focusRequests
        #expect(requests == [.point(FocusPoint(x: 0.25, y: 0.75))])
        #expect(rig.model.focusTap.marker?.viewPoint == CGPoint(x: 100, y: 300))
    }

    @Test func aBurstOfTapsSendsOnlyTheLatestWhileOneRuns() async throws {
        let rig = try await rig()
        await rig.fake.holdFocus()
        rig.model.focusTapped(at: CGPoint(x: 40, y: 40), in: Self.size)
        #expect(await until { await rig.fake.focusRequests.count == 1 })
        rig.model.focusTapped(at: CGPoint(x: 80, y: 80), in: Self.size)
        rig.model.focusTapped(at: CGPoint(x: 200, y: 120), in: Self.size)
        await rig.fake.resumeFocus()
        #expect(await eventually { rig.model.focusRequests.isIdle })
        let requests = await rig.fake.focusRequests
        #expect(requests.count == 2)
        #expect(requests.last == .point(FocusPoint(x: 0.5, y: 0.3)))
    }

    @Test func aTapNeverConfigures() async throws {
        let rig = try await rig()
        let configures = await rig.fake.applied.count
        let manual = rig.model.manual
        rig.model.focusTapped(at: CGPoint(x: 100, y: 100), in: Self.size)
        rig.model.focusHeld(at: CGPoint(x: 120, y: 100), in: Self.size)
        #expect(await eventually { rig.model.focusRequests.isIdle })
        #expect(await rig.fake.applied.count == configures)
        #expect(!(await rig.fake.calls.suffix(4).contains("configure")))
        #expect(rig.model.manual == manual)
        #expect(!rig.model.isViewfinderChanging)
    }

    @Test func aTapWorksWhileRecording() async throws {
        let rig = try await rig(mode: .video)
        rig.model.isRecording = true
        #expect(rig.model.canAim)
        rig.model.focusTapped(at: CGPoint(x: 100, y: 100), in: Self.size)
        #expect(await eventually { rig.model.focusRequests.isIdle })
        #expect(await focusCount(rig.fake) == 1)
        #expect(rig.model.focusTap.marker != nil)
    }

    @Test func aSliderMoveWhileLockedSendsRecentre() async throws {
        let rig = try await rig()
        rig.model.focusHeld(at: CGPoint(x: 100, y: 100), in: Self.size)
        #expect(await eventually { rig.model.focusRequests.isIdle })
        #expect(rig.model.focusTap.lockText == "AE/AF lock")
        rig.model.toggleControl(.iso)
        rig.model.setControl(.iso, step: 5)
        #expect(await eventually { rig.model.focusRequests.isIdle })
        #expect(await rig.fake.focusRequests.last == .recentre)
        #expect(rig.model.focusTap.lock == nil)
    }

    @Test func aLensChangeClearsTheLock() async throws {
        let rig = try await rig()
        rig.model.focusHeld(at: CGPoint(x: 100, y: 100), in: Self.size)
        #expect(rig.model.focusTap.lock != nil)
        rig.model.selectLens("ultraWide")
        #expect(rig.model.focusTap.lock == nil); #expect(rig.model.focusTap.marker == nil)
        await rig.model.waitForQueuedConfigures()
    }

    @Test func withBothSetByHandATapSendsNothing() async throws {
        let rig = try await rig()
        var both = ManualSettings()
        both.focus = 0.4
        both.exposure = .manual(shutterSeconds: 0.01, iso: nil)
        rig.model.manual = both
        rig.model.focusTapped(at: CGPoint(x: 100, y: 100), in: Self.size)
        rig.model.focusHeld(at: CGPoint(x: 100, y: 100), in: Self.size)
        #expect(rig.model.focusTap.marker == nil)
        try await Task.sleep(for: .milliseconds(50))
        #expect(await focusCount(rig.fake) == 0)
    }

    @Test func inTheSimulatorATapShowsTheMarkerWithoutASession() throws {
        let model = CameraModel(config: .parse(["app", "-mode", "photo"]), capabilities: try Fixture.load(), isSimulator: true, defaults: try Fixture.freshDefaults())
        #expect(model.canAim)
        model.focusTapped(at: CGPoint(x: 100, y: 100), in: Self.size)
        #expect(model.focusTap.marker?.viewPoint == CGPoint(x: 100, y: 100))
        model.focusHeld(at: CGPoint(x: 200, y: 100), in: Self.size)
        #expect(model.focusTap.lockText == "AE/AF lock")
        let serial = model.focusTap.marker?.serial ?? 0
        model.focusMarkerFaded(serial: serial)
        #expect(model.focusTap.marker?.isLocked == true)
    }

    @Test func noTapWhileTheViewfinderChanges() async throws {
        let rig = try await rig()
        await rig.fake.holdConfigures()
        rig.model.mode = .video
        #expect(rig.model.isViewfinderChanging)
        #expect(!rig.model.canAim)
        rig.model.focusTapped(at: CGPoint(x: 100, y: 100), in: Self.size)
        rig.model.focusHeld(at: CGPoint(x: 100, y: 100), in: Self.size)
        #expect(rig.model.focusTap.marker == nil)
        await rig.fake.resumeConfigures()
        await rig.model.waitForQueuedConfigures()
        #expect(await focusCount(rig.fake) == 0)
    }
}
