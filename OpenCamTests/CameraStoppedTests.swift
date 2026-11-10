import AVFoundation
import Foundation
import Testing
@testable import OpenCam

/// A camera session that stops with a runtime error goes back to a selection that works, or says the camera stopped while
/// Mode, Lens, Record settings and Try again still work. The confirmation delay is shortened so no test waits 1.5 s.
@MainActor @Suite struct CameraStoppedTests {
    private static let stop = "[CameraSession:runtimeError] Session stopped — {domain: AVFoundationErrorDomain, code: -11800, The operation could not be completed}"
    private static let uhd = Resolution.named(width: 3840, height: 2160)
    private static let other = RecordSelection(family: .proRes, quality: "422 HQ", resolution: uhd, frameRate: 30, colour: .rec709)

    /// A model attached to a fake session, as `start(session:)` leaves it, with a short confirmation delay. With `saved`,
    /// those selections are restored at launch.
    private func attachedModel(saved: SavedSelections? = nil) throws -> (CameraModel, FakeSessionConfigurator, UserDefaults) {
        let defaults = try Fixture.freshDefaults()
        saved?.save(to: defaults)
        let model = CameraModel(config: LaunchConfig(), capabilities: try Fixture.load(), isSimulator: false, defaults: defaults,
                                captureStore: try CaptureStore(directory: TestFiles.directory()))
        model.confirmationDelay = .milliseconds(40)
        model.phase = .ready
        let fake = FakeSessionConfigurator(failingLensIDs: [])
        let configuration = try #require(model.sessionConfiguration)
        model.attachSession(fake, configuredWith: configuration, selection: model.currentSelection)
        // As `start(session:)` does once the session's start has returned.
        model.confirmWhenRunning(configuration, since: model.runtimeErrorCount)
        return (model, fake, defaults)
    }

    /// The selection a first launch picks, read from a model with nothing saved.
    private func firstLaunchSelection() throws -> SavedSelections {
        let model = CameraModel(config: LaunchConfig(), capabilities: try Fixture.load(), isSimulator: false, defaults: try Fixture.freshDefaults())
        return model.currentSelection
    }

    private func confirmed(_ model: CameraModel) async -> Bool {
        await eventually { model.confirmed?.selection == model.currentSelection }
    }

    private func starts(_ fake: FakeSessionConfigurator) async -> Int {
        await fake.calls.filter { $0 == "start" }.count
    }

    @Test func aSelectionThatFailsOnceRunningGoesBackToTheConfirmedOne() async throws {
        let (model, fake, defaults) = try attachedModel()
        let first = model.currentSelection
        let firstConfiguration = try #require(model.sessionConfiguration)
        #expect(await confirmed(model))
        model.record = Self.other
        await model.waitForQueuedConfigures()
        #expect(await fake.applied.count == 1)
        model.apply(.runtimeError(Self.stop))
        await model.waitForQueuedConfigures()
        #expect(model.currentSelection == first)
        #expect(SavedSelections.load(from: defaults) == first)
        #expect(await fake.applied.last == firstConfiguration); #expect(await fake.applied.count == 2)
        #expect(await fake.calls.last == "start")
        #expect(model.notice == "That format could not be used.")
        #expect(await eventually { model.phase == .ready })
        #expect(model.currentSelection == first); #expect(model.notice == "That format could not be used.")
    }

    @Test func aSelectionThatStopsTheCameraAtLaunchIsReplacedByTheDefault() async throws {
        var saved = try firstLaunchSelection()
        let defaultSelection = saved
        saved.record = Self.other
        let (model, fake, defaults) = try attachedModel(saved: saved)
        #expect(model.record == Self.other)
        model.apply(.runtimeError(Self.stop))
        await model.waitForQueuedConfigures()
        #expect(model.currentSelection == defaultSelection)
        #expect(SavedSelections.load(from: defaults) == defaultSelection)
        #expect(await fake.applied == [try #require(model.sessionConfiguration)])
        #expect(await fake.calls == ["configure", "start"])
        #expect(model.notice == "That format could not be used.")
        #expect(model.phase == .failed("The camera stopped."))
        #expect(await eventually { model.phase == .ready })
        #expect(model.confirmed?.selection == defaultSelection)
    }

    @Test func aStopOnAConfirmedSelectionRestartsItOnceWithoutChangingIt() async throws {
        let (model, fake, defaults) = try attachedModel()
        let selection = model.currentSelection
        let configuration = try #require(model.sessionConfiguration)
        let savedBefore = SavedSelections.load(from: defaults)
        #expect(await confirmed(model))
        model.apply(.runtimeError(Self.stop))
        await model.waitForQueuedConfigures()
        #expect(model.currentSelection == selection); #expect(SavedSelections.load(from: defaults) == savedBefore)
        #expect(model.notice == nil)
        #expect(await fake.applied == [configuration]); #expect(await fake.calls == ["configure", "start"])
        #expect(await eventually { model.phase == .ready })
        #expect(model.notice == nil)
    }

    @Test func aSecondStopDuringRecoveryEndsInTheStoppedState() async throws {
        let (model, fake, _) = try attachedModel()
        let first = model.currentSelection
        #expect(await confirmed(model))
        model.record = Self.other
        await model.waitForQueuedConfigures()
        model.apply(.runtimeError(Self.stop))
        await model.waitForQueuedConfigures()
        #expect(await fake.applied.count == 2)
        model.apply(.runtimeError(Self.stop))
        await model.waitForQueuedConfigures()
        #expect(model.phase == .failed("The camera stopped.")); #expect(model.isCameraStopped)
        // Well past the confirmation delay, nothing has brought the camera back or configured it again.
        try await Task.sleep(for: .milliseconds(200))
        #expect(model.phase == .failed("The camera stopped."))
        #expect(await fake.applied.count == 2); #expect(await starts(fake) == 1)
        #expect(model.currentSelection == first); #expect(model.notice == "That format could not be used.")
    }

    @Test func theStoppedStateKeepsRecordSettingsAndRetryUsable() async throws {
        let (model, fake, _) = try attachedModel()
        #expect(await confirmed(model))
        try await stopTwice(model)
        #expect(model.isCameraStopped)
        #expect(model.canOpenRecordSettings); #expect(model.canChangeLensOrMode); #expect(!model.canCapture)
        let startsBefore = await starts(fake)
        model.record = Self.other
        await model.waitForQueuedConfigures()
        #expect(await fake.applied.last == model.sessionConfiguration)
        #expect(await starts(fake) == startsBefore + 1)
        #expect(await eventually { model.phase == .ready })
        #expect(model.record == Self.other); #expect(model.canCapture)

        #expect(await confirmed(model))
        try await stopTwice(model)
        #expect(model.isCameraStopped)
        let appliedBefore = await fake.applied.count
        let startsBeforeRetry = await starts(fake)
        model.retryCamera()
        await model.waitForQueuedConfigures()
        #expect(await fake.applied.count == appliedBefore + 1); #expect(await fake.applied.last == model.sessionConfiguration)
        #expect(await starts(fake) == startsBeforeRetry + 1)
        #expect(await eventually { model.phase == .ready })
        #expect(model.record == Self.other)
    }

    @Test func aRecoveryWhoseConfigureThrowsEndsInTheStoppedState() async throws {
        let (model, fake, _) = try attachedModel()
        let selection = model.currentSelection
        #expect(await confirmed(model))
        await fake.setFailingLensIDs([model.lensID])
        model.apply(.runtimeError(Self.stop))
        await model.waitForQueuedConfigures()
        #expect(model.phase == .failed("The camera stopped.")); #expect(model.isCameraStopped)
        #expect(await fake.calls.isEmpty)
        try await Task.sleep(for: .milliseconds(200))
        #expect(model.phase == .failed("The camera stopped.")); #expect(model.currentSelection == selection)
        #expect(model.notice == nil); #expect(await starts(fake) == 0)
    }

    /// A configuration that runs past the confirmation and then stops again is restarted automatically only once; Try again
    /// gives one more automatic restart.
    @Test func aSelectionThatKeepsStoppingAfterItsRestartEndsInTheStoppedState() async throws {
        let (model, fake, _) = try attachedModel()
        let configuration = try #require(model.sessionConfiguration)
        #expect(await confirmed(model))
        model.apply(.runtimeError(Self.stop))
        await model.waitForQueuedConfigures()
        #expect(await eventually { model.phase == .ready })
        model.apply(.runtimeError(Self.stop))
        await model.waitForQueuedConfigures()
        #expect(model.isCameraStopped)
        try await Task.sleep(for: .milliseconds(200))
        #expect(model.phase == .failed("The camera stopped."))
        #expect(await fake.calls == ["configure", "start"]); #expect(await fake.applied == [configuration])
        model.retryCamera()
        await model.waitForQueuedConfigures()
        #expect(await eventually { model.phase == .ready })
        #expect(await fake.calls == ["configure", "start", "configure", "start"])
        model.apply(.runtimeError(Self.stop))
        await model.waitForQueuedConfigures()
        #expect(await fake.calls == ["configure", "start", "configure", "start", "configure", "start"])
        #expect(await eventually { model.phase == .ready })
    }

    /// A runtime error handled while the recovery's start is still awaited stops its confirmation.
    @Test func aStopDuringTheRestartsStartIsNotLost() async throws {
        let (model, fake, _) = try attachedModel()
        #expect(await confirmed(model))
        await fake.setOnNextStart { @MainActor in model.apply(.runtimeError(Self.stop)) }
        model.apply(.runtimeError(Self.stop))
        await model.waitForQueuedConfigures()
        #expect(await fake.calls == ["configure", "start"])
        try await Task.sleep(for: .milliseconds(200))
        #expect(model.phase == .failed("The camera stopped.")); #expect(model.isCameraStopped)
    }

    /// The Library's return is the one recovery: a runtime error during its start leaves the camera stopped, not ready.
    @Test func aStopDuringTheReturnFromTheLibraryEndsInTheStoppedState() async throws {
        let (model, fake, _) = try attachedModel()
        model.openLibrary()
        await model.libraryHandoff?.value
        await fake.setOnNextStart { @MainActor in model.apply(.runtimeError(Self.stop)) }
        model.isLibraryPresented = false
        await model.closeLibrary()
        #expect(await fake.calls == ["release", "configure", "start"])
        #expect(model.phase == .failed("The camera stopped.")); #expect(model.isCameraStopped)
        try await Task.sleep(for: .milliseconds(200))
        #expect(model.phase == .failed("The camera stopped."))
    }

    /// A confirmation armed just before a media-services reset never marks the camera ready, and nothing starts the session
    /// beside the reset's own restart; `.restarted` does.
    @Test func aConfirmationArmedBeforeAResetNeverMarksTheCameraReady() async throws {
        let (model, fake, _) = try attachedModel()
        model.apply(.runtimeError("[CameraSession:runtimeError] Session stopped — {code: -11819}"))
        #expect(!model.isCameraStopped); #expect(!model.canOpenRecordSettings)
        model.retryCamera()
        await model.waitForQueuedConfigures()
        try await Task.sleep(for: .milliseconds(200))
        #expect(model.phase == .failed("The camera stopped.")); #expect(model.confirmed == nil); #expect(await fake.calls.isEmpty)
        model.apply(.restarted)
        #expect(model.phase == .ready)
    }

    /// What `CameraSession` writes for a reset is recognised as one; a -11800, a -11819 from another domain, or a -11819
    /// only as the underlying error is not.
    @Test func theSessionsResetMessageIsRecognisedAndNoOtherIs() {
        let applied = "lens: wide, mode: video"
        let reset = RuntimeErrorText.message(for: NSError(domain: AVFoundationErrorDomain, code: -11819), applied: applied)
        #expect(CameraModel.isMediaServicesReset(reset))
        let stopped = RuntimeErrorText.message(for: NSError(domain: AVFoundationErrorDomain, code: -11800), applied: applied)
        #expect(!CameraModel.isMediaServicesReset(stopped))
        let otherDomain = RuntimeErrorText.message(for: NSError(domain: NSOSStatusErrorDomain, code: -11819), applied: applied)
        #expect(!CameraModel.isMediaServicesReset(otherDomain))
        let underlying = NSError(domain: AVFoundationErrorDomain, code: -11800,
                                 userInfo: [NSUnderlyingErrorKey: NSError(domain: AVFoundationErrorDomain, code: -11819)])
        let wrapped = RuntimeErrorText.message(for: underlying, applied: applied)
        #expect(wrapped.contains("underlying: AVFoundationErrorDomain -11819")); #expect(wrapped.hasSuffix("lens: wide, mode: video}"))
        #expect(!CameraModel.isMediaServicesReset(wrapped))
    }

    /// A confirmation armed for a sweep option never confirms it once a failed restore has moved the chain on, though the
    /// session is left on that option.
    @Test func aConfirmationTheChainHasMovedPastConfirmsNothing() async throws {
        let (model, fake, _) = try attachedModel()
        let user = model.currentSelection
        #expect(await confirmed(model))
        model.confirmationDelay = .milliseconds(300)
        model.isSweeping = true
        model.record = Self.other
        await model.waitForQueuedConfigures()
        await fake.setFailingLensIDs([model.lensID])
        model.record = user.record
        await model.waitForQueuedConfigures()
        #expect(model.record == Self.other)
        model.isSweeping = false
        try await Task.sleep(for: .milliseconds(500))
        #expect(model.confirmed?.selection == user)
    }

    /// A reset while the camera is released for the Library brings no `.restarted`; the Library's return configures and
    /// starts the camera as usual and it is ready again.
    @Test func aResetWhileReleasedForTheLibraryEndsReadyAfterTheReturn() async throws {
        let (model, fake, _) = try attachedModel()
        model.openLibrary()
        await model.libraryHandoff?.value
        model.apply(.runtimeError("[CameraSession:runtimeError] Session stopped — {code: -11819}"))
        #expect(!model.isResettingMediaServices)
        model.isLibraryPresented = false
        await model.closeLibrary()
        #expect(await fake.calls == ["release", "configure", "start"])
        #expect(await eventually { model.phase == .ready })
        #expect(model.canOpenRecordSettings)
    }

    /// Going back to the confirmed selection uses the same once-only allowance: when that selection then stops again with no
    /// user action, the camera is stopped, after exactly one automatic configure and start.
    @Test func aConfirmedSelectionRestoredOnceIsNotRestoredOrRestartedAgain() async throws {
        let (model, fake, _) = try attachedModel()
        let first = model.currentSelection
        let firstConfiguration = try #require(model.sessionConfiguration)
        #expect(await confirmed(model))
        model.record = Self.other
        await model.waitForQueuedConfigures()
        model.apply(.runtimeError(Self.stop))
        await model.waitForQueuedConfigures()
        #expect(await eventually { model.phase == .ready })
        #expect(model.currentSelection == first)
        model.apply(.runtimeError(Self.stop))
        await model.waitForQueuedConfigures()
        try await Task.sleep(for: .milliseconds(200))
        #expect(model.isCameraStopped)
        // The user's change configured once; the recovery configured and started once.
        #expect(await fake.calls == ["configure", "configure", "start"]); #expect(await fake.applied.last == firstConfiguration)
    }

    /// The clip ends as it always has; only then does the camera restart.
    @Test func aStopWhileRecordingRecoversOnceTheClipHasEnded() async throws {
        let (model, fake, _) = try attachedModel()
        let option = try #require(model.currentVideoOption)
        #expect(await confirmed(model))
        model.isRecording = true
        model.apply(.runtimeError(Self.stop))
        await model.waitForQueuedConfigures()
        #expect(model.phase == .failed("The camera stopped.")); #expect(await fake.calls.isEmpty)
        model.recordingDidFinish(RecordingResult(url: URL(filePath: "/tmp/OC_0009.MOV"), option: option,
                                                 outcome: .stopped(.other(code: -11800), isPlayable: false), sidecar: nil))
        await model.waitForQueuedConfigures()
        #expect(!model.isRecording); #expect(await fake.calls == ["configure", "start"])
        #expect(await eventually { model.phase == .ready })
    }

    /// The confirmed selection stops, its one restart stops too: the stopped state.
    private func stopTwice(_ model: CameraModel) async throws {
        model.apply(.runtimeError(Self.stop))
        await model.waitForQueuedConfigures()
        model.apply(.runtimeError(Self.stop))
        await model.waitForQueuedConfigures()
        #expect(model.phase == .failed("The camera stopped."))
    }
}
