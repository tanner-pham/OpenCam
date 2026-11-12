# OpenCam Launch Fast Path Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On a launch with camera access granted and a configuration the last run confirmed, the session starts from that configuration at once, with its preview already attached, while lenses and capabilities are read, and the journal says where each launch millisecond went.

**Architecture:** The session actor starts itself from a small saved record (`SavedStart`) in a detached task; the model is not attached to it and no model state changes. `CameraModel.start` runs today's sequence up to the first configure and there either adopts the saved start (the configuration it applied equals the resolved one as a whole, so the configure call is skipped) or releases it and runs today's path. From `attachSession` onward the code is today's, so `lastWorking`, the 1.5 s confirmation and the one automatic restart are armed exactly as now.

**Tech Stack:** Swift 6 (MainActor default isolation, approachable concurrency), SwiftUI, AVFoundation, Swift Testing. No new dependencies.

**Spec:** The owner, 2026-11-11: "The camera takes a long time to start, making it almost unusable fast. We need to figure out a way to get fast boots into the camera." Measured on the phone (Release, valid capability cache, `docs/research/duo-timing-journal-2026-11-11.log`): `[timing] launch model 82 ms, capabilities 617 ms, configured 626 ms, running 1602 ms`; `[timing] cache load (off the main actor) 43 ms`; `[timing] preview attach 192 ms` just after `running`. So about 535 ms pass before the session is configured, the configure costs 9 ms, and `startRunning` costs about 976 ms.

## What the code says about the idea

The idea works, with one change of shape and two additions. Line numbers are from `feat/option-data-rate`.

1. **It works as a join, not as an early attach.** `start(session:)` is serial (`OpenCam/App/CameraModel.swift:750-800`): free space, the failed-combinations file, `requestAccess`, lens discovery, cache load and adopt all come before `session.configure` (:776) and `session.start()` (:790). Configure and start need only a `SessionConfiguration`, and the session is an actor on its own queue (`OpenCam/Capture/CameraSession.swift:6`, :48). Attaching the model to the session before capabilities exist would put recovery in a state it has never run in (`configurator` set, no lens, `defaultSelection` nil). So the saved start touches no model state and the model joins at the configure step.
2. **`SavedSelections` and the cache are not enough.** `SessionConfiguration` holds a whole `Lens`, `VideoOption` and `PhotoOption` (`OpenCam/Capture/SessionConfiguration.swift:5-12`). `SavedSelections` holds only `lensID`, a `RecordSelection` and a `PhotoSelection` (megapixels, no width or height; no `codecType` or `bitrateTier`) (`OpenCam/Support/SavedSelections.swift:4-12`). The rest lives only in the 2.4 MB list. The model also compares configurations with `==` (`CameraModel.swift:625-626`), so an approximated one would always look different. Task 3 saves the smallest exact record.
3. **Addition: the preview joins the session too late.** `ViewfinderArea` builds `CameraPreviewView` only in `.ready` (`OpenCam/UI/ViewfinderArea.swift:38-41`), and `PreviewUIView.init` attaches the layer there (`OpenCam/UI/PreviewUIView.swift:43`). The measured 192 ms is a preview layer joining a running session, on the main thread, after `running`. The SDK (iPhoneOS27.2) adds a second cost, not measured here: photo and file outputs default to deferred start for apps linked on iOS 26 or later (`AVCaptureOutputBase.h:126`), preview layers default to not deferred, and every output having the same value "is equivalent to not using deferred start" (`AVCaptureVideoPreviewLayer.h:271-273`); deferred start runs "a short time after displaying the first frame" (`AVCaptureSession.h:659`). Today the session starts with no preview layer, so nothing can be deferred. Task 2 attaches the layer first.
4. **Addition: the look renderer.** Its warm-up overlaps `startRunning` today (`CameraModel.swift:787`). With the session already running at the join, the phase would turn ready before the warm-up ran. Task 4 starts it with the saved start.
5. **"As early as possible" stops at the first statement of `start(session:)`.** The preview layer is a UIKit view and must exist before the session starts (point 3). `OpenCamApp.init` (`OpenCam/App/OpenCamApp.swift:22-50`) is, to my knowledge, called before `UIApplicationMain`, where no view can be made and where iOS prewarming can run the process with nobody looking; neither is verifiable from this repo. Task 1's `start` mark says what an earlier start would save; see Open questions.
6. **The screen does not change.** The phase stays `.scanning` until the session runs and the capabilities are adopted, then `.ready`. By the measurements the window "running, no capabilities" is empty: capabilities are ready at 617 ms and the session cannot run before about `start` + 985 ms. Showing the picture earlier would need a new phase read by `hasCamera`, `canCapture`, `canOpenRecordSettings`, `canRescanCapabilities` and the recovery guards.
7. **The microphone's share cannot be seen by timing its attach.** The whole first configure is 9 ms. The microphone is attached in both modes (`CameraSession.swift:149`, `SessionConfiguration.swift:18`). Task 1 notes `audio yes|no` beside the `startRunning` time; one launch with the microphone off in Settings gives the comparison.
8. **No test runs the start sequence today.** `start(session:)` takes the concrete `CameraSession`; `CameraStoppedTests.attachedModel` copies its last lines by hand (`OpenCamTests/CameraStoppedTests.swift:13-27`). Task 4 first moves the sequence behind `SessionConfigurator`.

## Global Constraints

- Branch `perf/launch-fast-path`, from `feat/option-data-rate`.
- The camera core plan's constraints apply: strict Swift 6 concurrency, no force unwraps or `try!`, one type per file, errors as `[Module:Function] Description — {context}`, no new `@unchecked Sendable`, no `nonisolated(unsafe)`, no `@preconcurrency import`, conventional commits, API facts only from `docs/research/capture-apis.md` or the SDK headers.
- Recovery: nothing changes about when a configuration is confirmed, restarted or restored. `CameraModel+Recovery.swift` gains exactly one call (Task 3).
- A saved start is adopted only when the configuration it applied equals the resolved one as a whole. Otherwise the session is released and today's path runs. It is never patched live.
- No camera runs behind a format scan, a failure screen or a denial.
- A fallback is silent: no notice and no phase today's path would not show, and exactly one journal line.
- The saved start goes through `CameraSession.configure(_:)`. The photo preset and the hand-set video format stay in that one place.
- The microphone is attached as today. Nothing defers it.
- `CameraRootView` is not touched; `onCameraCaptureEvent` stays on the NavigationStack's content.
- The Simulator has no session (`OpenCamApp.swift:42`), so nothing new runs there.
- No user-facing copy changes.

## Review Focus

1. A camera left running behind a scan or a failure after a saved start. Pinned by `CameraLaunchTests.aSavedStartIsReleasedBeforeTheScan` and `aStartThatFailsAfterASavedStartLeavesNoCameraRunning` (Task 4).
2. A saved start trusted sooner than a normal start: confirmed or saved before it ran 1.5 s under the model, or a runtime error during it lost. Pinned by `aSavedStartIsConfirmedOnlyAfterTheDelay` and `aStopRightAfterASavedStartRecoversLikeANormalStart` (Task 4).
3. A stale record starting a camera or format this launch would not choose: OS update, scan version bump, a selection changed just before the app was killed, microphone access changed, a look turned on or off. Pinned by the four `aRecordIsUsedOnly…` tests in `SavedStartTests` (Task 3).
4. A saved start that is almost right being patched on a running session, leaving a state today's path never produces. Pinned by `aSavedStartThatDiffersIsDiscardedNotPatched`, once per field (Task 4).
5. A notice or failed screen because the saved start failed although the normal path works. Pinned by `aSavedStartThatCouldNotBeConfiguredIsSilent` (Task 4).

---

### Task 1: Launch marks

**Files:**
- Modify: `OpenCam/Support/LaunchTimeline.swift`, `OpenCam/App/CameraModel.swift` (`start(session:)`), `OpenCam/App/CameraModel+Scan.swift` (`loadCapabilities`), `OpenCam/Capture/CameraSession.swift` (`configure`, `start`), `OpenCam/UI/PreviewUIView.swift`
- Test: create `OpenCamTests/LaunchTimelineTests.swift`

**Interfaces:**
- Consumes: `LaunchTimeline.mark(_:at:)`, `ErrorJournal.record(_:)`, `CameraModel.launchTimeline`.
- Produces:
  - `mutating func note(_ text: String)` on `LaunchTimeline`: appends `text` as written, in order with the marks.
  - The model's line gains marks: `[timing] launch model N ms, start N ms, access N ms, lenses N ms, cache N ms, capabilities N ms, configured N ms, running N ms`. `start` is the first statement of `start(session:)`; `access` follows `requestAccess`; `lenses` follows discovery; `cache` follows the cache load in `loadCapabilities`, before the adopt.
  - A session line, written once, when the first `start()` returns: `[timing] launch session configure N ms, session configured N ms, session startRunning N ms, session running N ms, session started N ms, video 1x, audio yes, preview no`. `session configure` and `session configured` wrap each `configure` until that first start; `session startRunning` and `session running` wrap `session.startRunning()` alone; `session started` follows `allowHapticsWhileRecording()`. The notes are the applied mode and lens label, `audio yes|no` (`audioInput != nil`) and `preview yes|no` (`session.connections.contains { $0.videoPreviewLayer != nil }`). State: `private var launchMarks: LaunchTimeline?`, nil once written.
  - A preview line, once: `[timing] launch first picture N ms`, the first time `previewLayer.isPreviewing` is true while the view is in a window.
- Why the preview layer: `isPreviewing` is "currently rendering video frames" and is meant to be observed (`AVCaptureVideoPreviewLayer.h:127-135`). It is the picture in every mode and costs one key-value observation. The frame pipeline only runs with a look. `didStartRunningNotification` only repeats what `session running` already says.

- [ ] **Step 1: Write the failing tests** in `LaunchTimelineTests`:
  - `marksAndNotesKeepTheirOrderInOneLine`: with `processStart` at 100 s, `mark("model", at: 100.082)`, `mark("start", at: 100.240)`, `note("audio yes")` give `line == "[timing] launch model 82 ms, start 240 ms, audio yes"`.
  - `aMarkRoundsToTheNearestMillisecond`: a mark at 100.0006 s reads `1 ms`.
- [ ] **Step 2: Run and see them fail.** `scripts/test.sh LaunchTimelineTests`, exit 65 (no `note`).
- [ ] **Step 3: Implement.** In `PreviewUIView`, observe `\.isPreviewing` with `[.initial, .new]`, hop to the main actor (the header names no delivery queue), and check again in `didMoveToWindow`; an instance flag makes it once. Build the line with a fresh `LaunchTimeline()` so all three lines share the process-start clock. The marks in `start`, the session and the preview have no unit test: the Simulator has no camera. The phone's journal is their check.
- [ ] **Step 4: Run.** `scripts/test.sh LaunchTimelineTests` exit 0; `scripts/test.sh` exit 0; device SDK build with 0 warnings.
- [ ] **Step 5: Commit.** `perf: journal each launch phase, the session's own start and the first picture`

### Task 2: The preview joins the session before it starts

**Files:**
- Modify: `OpenCam/App/OpenCamApp.swift` (the `.task` that calls `model.start`), `OpenCam/UI/PreviewUIView.swift` (the comment on `shared(for:)`)
- Test: create `OpenCamTests/PreviewUIViewTests.swift`

**Interfaces:**
- Consumes: `PreviewUIView.shared(for:)`, `CameraSession.previewSource`.
- Produces: no new names. In the `.task`, after the `guard`, `_ = PreviewUIView.shared(for: session.previewSource)` runs before `await model.start(session: session)`. `CameraPreviewView.makeUIView` later receives the same view.

- [ ] **Step 1: Write the test** `theSharedPreviewIsMadeOncePerSession`: for one `PreviewSource(session: AVCaptureSession(), frames: FramePipeline())`, two calls to `shared(for:)` return the same instance, and its layer's `session` is the source's. This passes before the change. It pins what the change relies on; the ordering itself can only be seen on the phone.
- [ ] **Step 2: Implement** the one statement, with a comment giving the reason and the two header lines from point 3 above.
- [ ] **Step 3: Run.** `scripts/test.sh PreviewUIViewTests`, `scripts/test.sh`, device SDK build.
- [ ] **Step 4: Commit.** `perf: attach the preview before the session starts`

Accept or revert this task alone on the phone checks at the end.

### Task 3: The saved start record

**Files:**
- Create: `OpenCam/Support/SavedStart.swift`
- Modify: `OpenCam/Capture/SessionConfiguration.swift` (add `Codable`), `OpenCam/App/CameraModel.swift` (two small functions beside `persist()`, which share its private `defaults` and `isScripted`), `OpenCam/App/CameraModel+Recovery.swift` (one call), `OpenCam/App/CameraModel+Scan.swift` (`rescanCapabilities`)
- Test: create `OpenCamTests/SavedStartTests.swift`; modify `OpenCamTests/CameraStoppedTests.swift`, `OpenCamTests/CapabilityRescanTests.swift`

**Interfaces:**
- Consumes: `SessionConfiguration`, `SavedSelections`, `RecordSelection`, `PhotoSelection`, `CaptureAccess`, `LookAvailability.isOffered(mode:colour:)`, `CaptureCapabilities.currentScanVersion`, `CameraModel.lastWorking`, `capabilities`.
- Produces:

```swift
nonisolated struct SavedStart: Codable, Sendable, Equatable {
    static let key = "savedStart"          // UserDefaults, beside "savedSelections"
    var configuration: SessionConfiguration
    var record: RecordSelection            // what `configuration` was resolved from
    var photo: PhotoSelection
    var osBuild: String                    // of the capabilities it was resolved against
    var modelIdentifier: String
    var scanVersion: Int
    static func load(from defaults: UserDefaults) -> SavedStart?
    func save(to defaults: UserDefaults)
    static func clear(from defaults: UserDefaults)
    func configuration(for saved: SavedSelections?, access: CaptureAccess, hasLook: Bool,
                       osBuild: String, modelIdentifier: String) -> SessionConfiguration?
}
extension CameraModel {
    func saveStart(_ working: (configuration: SessionConfiguration, selection: SavedSelections))
    func clearSavedStart()
}
```

`configuration(for:…)` returns `configuration` only when all of these hold, else nil:
1. `osBuild` and `modelIdentifier` match and `scanVersion == CaptureCapabilities.currentScanVersion` (the cache's own rule, `CapabilityCache.swift:19-20`).
2. `saved` is not nil, and `saved.mode == configuration.mode`, `saved.lensID == configuration.lens.id`, `saved.record == record`, `saved.photo == photo`. The look's content is not compared.
3. `access.camera == .authorized`, `access.microphone != .notDetermined`, and `configuration.includesAudio == access.recordsSound`.
4. `configuration.needsFrames == (hasLook && LookAvailability.isOffered(mode: configuration.mode, colour: record.colour))`.

`saveStart` does nothing on a scripted launch; otherwise it saves `working` with `capabilities.osBuild`, `.modelIdentifier` and `.scanVersion`. It is called in `confirmWhenRunning` on the line after `confirmed = lastWorking` (`CameraModel+Recovery.swift:105`), so the record is written exactly where a configuration is confirmed and nowhere else. `rescanCapabilities` calls `clearSavedStart()` where it clears the cache (`CameraModel+Scan.swift:38`).

- [ ] **Step 1: Write the failing tests.**
  - `SavedStartTests.aRecordRoundTripsThroughDefaults`: saved then loaded is equal; after `clear`, nil; other bytes under the key, nil.
  - `aRecordIsUsedOnlyOnItsOwnBuildModelAndScan`: another `osBuild`, another `modelIdentifier`, and `scanVersion` one lower each give nil; all matching gives the configuration.
  - `aRecordIsUsedOnlyForTheSelectionSavedNow`: `saved == nil` gives nil; a different mode, lens, record or photo each gives nil; a different `look` alone still gives the configuration.
  - `aRecordIsUsedOnlyWithTheAccessItWasBuiltFor`: camera `.notDetermined`, `.denied`, `.restricted` each nil; microphone `.notDetermined` nil; `includesAudio` true with the microphone denied nil; false with it authorized nil; false with it denied gives the configuration.
  - `aRecordIsUsedOnlyWhenItsFramesMatchTheLook`: `needsFrames` false with a look in Rec. 709 video nil; true with no look nil; false with a look in Apple Log video gives the configuration; true with a look in photo gives the configuration.
  - `CameraStoppedTests.aConfirmedConfigurationIsSavedAsTheNextStart`: `SavedStart.load` is nil before the confirmation; after it, it equals the record built from the model's configuration, record, photo and the capabilities' build, model and scan version.
  - `CameraStoppedTests.aConfigurationThatStopsBeforeItsConfirmationIsNeverSaved`: confirm a first selection; change the record; deliver `.runtimeError` before the new one is confirmed; right then and after the recovery is confirmed, the saved start's configuration is the first one's.
  - `CameraStoppedTests.aScriptedLaunchSavesNoStart`: a `-mode photo` model, attached and confirmed, leaves `SavedStart.load` nil.
  - `CapabilityRescanTests.aRescanClearsTheSavedStart`: with a record saved, inside the scan hook `SavedStart.load` is nil.
- [ ] **Step 2: Run and see them fail.** `scripts/test.sh SavedStartTests`, exit 65.
- [ ] **Step 3: Implement** to the Interfaces. `SessionConfiguration` gains the `Codable` conformance only; every member already has it.
- [ ] **Step 4: Run.** The three suites, then `scripts/test.sh`; the existing recovery tests pass unchanged; device SDK build.
- [ ] **Step 5: Commit.** `feat: save the confirmed configuration as the next launch's start`

### Task 4: The fast path

**Files:**
- Create: `OpenCam/App/CameraModel+Launch.swift`, `OpenCam/Capture/CameraSession+SavedStart.swift`
- Modify: `OpenCam/App/CameraModel.swift` (`start(session:)`; `savedStartConfiguration(access:)` beside `saveStart`; `discoverLenses` moves out), `OpenCam/App/CameraModel+Scan.swift` (`loadCapabilities`), `OpenCam/Capture/CameraSession.swift` (`requestAccess` reads `currentAccess()`)
- Test: create `OpenCamTests/CameraLaunchTests.swift`

**Interfaces:**
- Consumes: `SavedStart` (Task 3), `LaunchTimeline.note` (Task 1), `SessionConfigurator`, `attachSession`, `confirmWhenRunning`, `watchFrames`, `releaseIfLibraryOpen`, `FakeSessionConfigurator` (`calls`, `applied`, `isRunning`, `holdsCamera`), `ScanHook`, `CapabilitySource`, `CapabilityCache`, `DeviceIdentity`.
- Produces:

```swift
// CameraSession+SavedStart.swift
extension CameraSession {
    /// What is already decided, without asking.
    nonisolated static func currentAccess() -> CaptureAccess
    /// Configures and starts `configuration` on the session's queue, in a detached task at `.userInitiated`, so it
    /// never waits for the main actor. The value is `configuration` once the start has returned, or nil when the
    /// configure threw, which is journalled once:
    /// "[CameraSession:startSaved] Saved start not used — {lens: …, mode: …, error: …}".
    nonisolated func startSaved(_ configuration: SessionConfiguration) -> Task<SessionConfiguration?, Never>
}
// CameraModel.swift
/// Nil on a scripted launch or when the record's rules say no. `hasLook` is `cameraLook != nil`.
func savedStartConfiguration(access: CaptureAccess) -> SessionConfiguration?
// CameraModel+Launch.swift
/// Today's sequence from `start(session:)`, lens discovery through the armed confirmation, over the protocol.
/// False, with the failed phase set and no camera running, when the camera cannot start.
func startCamera(on configurator: any SessionConfigurator, savedStart: Task<SessionConfiguration?, Never>?) async -> Bool
// CameraModel+Scan.swift
func loadCapabilities(lenses: [Lens], beforeScan: () async -> Void = {}) async
```

**How it plugs into recovery.** Until the join the model is as it is today at the same moment: `configurator`, `requestedConfiguration`, `lastWorking` and `confirmed` are nil and the phase is `.scanning`. `enqueueConfigure` returns nil without a configurator (`CameraModel.swift:625`), and no session event reaches the model, because the event loop starts after the sequence (:805) and the stream buffers. At the join, after `replaceCapabilities` has resolved the selection and `errors = runtimeErrorCount` has been read on the same line as today, the model awaits the saved start's value:
- Equal to `sessionConfiguration`: the `configure` call is skipped. Nothing else differs.
- Anything else (another configuration, or nil): the session is released with `releaseCameras()`, the state a rescan already configures and starts from (`CameraModel+Scan.swift:51-73`), and today's `configure` runs.

From there the lines are today's, in today's order: `attachSession(configurator, configuredWith: configuration, selection: selection)` sets `configurator`, `requestedConfiguration` and `lastWorking`; `configurator.start()` returns at once on a running session (`CameraSession.swift:195`); `phase = .ready`; `confirmWhenRunning(lastWorking.configuration, since: errors)`. `confirmed`, and with it the saved record, is set only 1.5 s after the join; time the saved start ran before the join does not count. A runtime error posted during the saved start is applied by the event loop after the join, where it cancels the confirmation and runs the one recovery, exactly as an error during today's `await session.start()` does.

- [ ] **Step 1: Write the failing tests for today's path** in `CameraLaunchTests`. The helper makes a model with empty capabilities, `isSimulator: false`, fresh defaults, a 40 ms `confirmationDelay`, and a `CapabilitySource` whose cache directory holds the fixture saved under `DeviceIdentity`'s build and model (as `CapabilityRescanTests` does). `expected` is the configuration a second model resolves from the same capabilities and defaults.
  - `aNormalStartConfiguresAttachesStartsAndConfirms`: `startCamera(on: fake, savedStart: nil)` is true; `fake.calls == ["configure", "start"]`; `fake.applied == [expected]`; the phase is `.ready`; `lastWorking?.configuration` and `requestedConfiguration` are `expected`; `confirmed` is nil at once and `expected`'s after the delay.
  - `aNormalStartWhoseConfigureThrowsFails`: with the resolved lens failing, false; the phase is `.failed("This format could not be set up.")`; `configurator` is nil; `fake.calls` is empty.
  - `aStartWithoutACacheScansFirst`: with no cache file, `fake.calls == ["configure", "start"]`, the phase is `.ready`, and the cache now loads.
- [ ] **Step 2: Run and see them fail.** `scripts/test.sh CameraLaunchTests`, exit 65 (no `startCamera`).
- [ ] **Step 3: Move, changing no behaviour.** Lines 758-800 of `start(session:)` become `startCamera(on:savedStart:)` in the new file, with `discoverLenses`; the parameter is ignored for now. `cameraSession = session` moves to just before the call. That is safe: its three readers are guarded by `phase == .ready` (`capturePhoto`, the sweep) or by `requestedConfiguration` (`watchFrames` through the chain). Run the suite.
- [ ] **Step 4: Commit.** `refactor: run the camera's start sequence over the session protocol`
- [ ] **Step 5: Write the failing tests for the saved start.**
  - `aSavedStartThatMatchesIsAdoptedWithoutAConfigure`: with `savedStart: Task { expected }`, true; `fake.calls == ["start"]`; `fake.applied` is empty; `lastWorking` is `(expected, model.currentSelection)`; `requestedConfiguration == expected`; the phase is `.ready`; `notice` is nil.
  - `aSavedStartIsConfirmedOnlyAfterTheDelay` (Review Focus 2): with a 300 ms delay, when `startCamera` returns `confirmed` is nil and `SavedStart.load` is what it was; after the delay it is confirmed and saved.
  - `aStopRightAfterASavedStartRecoversLikeANormalStart` (2): adopt, then `apply(.runtimeError)` before the delay; `fake.calls == ["start", "configure", "start"]`; `fake.applied == [expected]`; the selection is unchanged; no notice; the phase ends `.ready`.
  - `aSavedStartThatDiffersIsDiscardedNotPatched` (4): for `expected` changed in each of mode, lens, `video`, `photo`, `includesAudio` and `needsFrames`: `fake.calls == ["release", "configure", "start"]`, `fake.applied == [expected]`, the phase is `.ready`, `notice` is nil.
  - `aSavedStartThatCouldNotBeConfiguredIsSilent` (5): with `Task { nil }`, the same calls; `notice` is nil; the phase is `.ready`; the saved selections are as before.
  - `aSavedStartIsReleasedBeforeTheScan` (1): with no cache file, inside the scan hook the fake neither runs nor holds a camera; afterwards `fake.calls == ["release", "configure", "start"]`.
  - `aStartThatFailsAfterASavedStartLeavesNoCameraRunning` (1): for no lens discovered, a scan that throws, and a differing saved start whose normal configure throws: false; `fake.calls == ["release"]`; the fake is not running; the phase is today's (`"The camera could not start."` twice, `"This format could not be set up."` once); `configurator` is nil.
  - `aScriptedLaunchNeverStartsFromTheRecord`: `savedStartConfiguration(access:)` is nil for a `-mode video` model though a valid record and matching selections are saved; for `LaunchConfig()` it is the record's configuration.
  - `aSavedStartForAMissingCameraIsNil`: `await CameraSession().startSaved(expected).value == nil` (the Simulator has no such camera).
- [ ] **Step 6: Run and see them fail.**
- [ ] **Step 7: Implement.**
  - `start(session:)`, before anything is awaited: the `start` mark, then `savedStartConfiguration(access: CameraSession.currentAccess()).map { session.startSaved($0) }`. When that began, start the renderer warm-up task there too (same call and priority as :787, which stays and is a no-op once the renderer exists).
  - Every return before the attach discards a saved start first, including the access guard.
  - Discard: await the task, `releaseCameras()`, treat the saved start as absent from then on, and journal `[CameraModel:startCamera] Saved start released — {reason: …, lens: …, mode: …}` with reason `differs`, `format scan`, `no camera found`, `no lens selected` or `camera access`. When the value was nil the session has already written its line, so the model writes none.
  - `loadCapabilities` calls `beforeScan` after the cache miss, before the scan.
  - An adopted start adds the note `saved start` to the launch line.
  - `CameraModel+Recovery.swift` is not edited in this task.
- [ ] **Step 8: Run.** `scripts/test.sh CameraLaunchTests`, `CameraStoppedTests`, `CapabilityRescanTests`, then `scripts/test.sh` with totals; device SDK build with 0 warnings.
- [ ] **Step 9: Commit.** `perf: start the session from the last confirmed configuration while capabilities load`

**On the phone** (controller and owner), Release build, journal copied after each:
- [ ] After Task 1, the baseline: three `[timing] launch` lines per launch, video and photo. Keep the file in `docs/research/`.
- [ ] After Task 2: the session line says `preview yes`; no `preview attach` or `preview rotation update` line at launch; `first picture` is close to `running`; `session running − session startRunning` is not above the baseline. The picture is upright after a cold launch in each orientation. In photo mode three presses as the picture appears write three files; in video a recording started at once records.
- [ ] After Task 4, second launch: the launch line ends `saved start`; `session configure` is within a few ms of `start`; no "Saved start" line.
- [ ] Photo mode with RAW selected, relaunch: adopted, and a RAW press writes a DNG.
- [ ] Microphone off in Settings, relaunch: the normal path, "No microphone access" as today; the launch after is adopted with `audio no`. The difference in `session running − session startRunning` against `audio yes` is the microphone's share.
- [ ] Change the lens and close the app within a second; relaunch: the normal path, on the new lens.
- [ ] With a look selected in Rec. 709 video, relaunch: the look draws with no hitch as the picture appears.

## Not in this plan

- Starting before the first render. It needs an app delegate and a measured reason (Open question 1).
- Deferring the microphone, or leaving it out of photo mode.
- Showing the picture before the controls are filled in.
- Setting deferred start by hand (`deferredStartEnabled`, `automaticallyRunsDeferredStart`, `runDeferredStartWhenNeeded`). Task 2 only lets the defaults work.
- Making the 2.4 MB cache or its adoption cheaper. Both leave the critical path once the session starts beside them; the `lenses`, `cache` and `capabilities` marks will show if that stops being true.
- Using a saved start whose `includesAudio` or `needsFrames` no longer fits by substituting today's values.
- The "Reading camera formats…" line on a launch that reads nothing.

## Rulings on the open questions (controller, 2026-11-11)

1. **Starting before the first render:** not now. Decide from the `start − model` gap in the first journal with the new marks; over about 150 ms earns a follow-up through an app delegate, never `OpenCamApp.init`.
2. **Task 2 (preview before start) is an experiment.** It stays if the phone shows the first picture closer to `running` with no worse `startRunning`; otherwise it is reverted alone.
3. **The main thread waiting on the session:** read it off the journal; no change now.
4. **A changed microphone permission or look:** strict. That launch takes the normal path and the next is fast again.
5. **The microphone in photo mode:** left as it is until the `audio yes|no` comparison exists.
6. **A discarded saved start costs one stop:** accepted.
7. **A prewarmed launch shifts every mark:** accepted; differences between marks stay right.

**One install, not three.** The phone checks listed after Tasks 1, 2 and 4 are run from one build made after Task 4: the first launch after the install has no saved start, so it takes the normal path and is the baseline with the finer marks; the launches after it take the fast path.
