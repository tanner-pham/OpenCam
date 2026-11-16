# OpenCam Fast Lens Switch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. All paths are relative to the worktree root, `/Users/tannerpham/CS Projects/DuoCam/.claude/worktrees/feat+fast-lens-switch`.

**Goal:** In video at up to 60 fps the back lens buttons (0.5x, 1x, 2x) change lens on the combined back camera by a lens lock and a zoom, with no session reconfigure and no blur; photo mode, rates above 60 fps, the front cameras and manual shutter or ISO keep today's path.

**Architecture:** A `SessionConfiguration` gains `combined: CombinedLens?`, set by the model from a `CombinedCamera` read off the device at launch (property reads, no session, no cache change). The session attaches the camera the configuration names, locks it to the lens's own camera with iOS 27's lock-to-lens call, and, when a new configuration differs from the applied one only by lens, does only that lock and zoom. The blur rule and the saved start read the same field, so the model and the session cannot disagree about which camera is attached.

**Tech Stack:** Swift 6 (MainActor default isolation), SwiftUI, AVFoundation, Swift Testing. No new dependencies.

**Spec:** The owner asked for fast lens switching and, after the measurements, chose: go; (1A) use the combined camera while exposure is automatic, and the first manual shutter or ISO value moves the session to the lens's own camera behind today's blur; (2A) a lens tap returns white balance and focus to automatic, as today; (3A) lens taps stay disabled while recording, as today. The measurements are `duo-lens-check-2026-11-16.json` and `duo-lens-check-exposure-2026-11-16.json` (`docs/research`, git-ignored; taken with `-lensCheck` on branch `diag/dual-wide-check` at fa54a85).

## Read first: what the measurements decide

1. **Plain zoom is not a lens button.** With the default (auto) and the restricted switching behaviour the camera stayed on the ultra wide lens at zoom 2 and 4 in four of five sessions. `setPrimaryConstituentDeviceSwitchingBehaviorLockedWith(_:)` (AVCaptureDevice.h:878, iOS 27) changed lens in all 34 lens changes tried.
2. **Zoom on the combined camera.** Zoom 1 is the ultra wide lens (0.5x), 2 the wide lens (1x), 4 the wide lens cropped (2x): the camera's first lens starts at 1 and each next lens at its switch-over factor (`virtualDeviceSwitchOverVideoZoomFactors`, here `[2]`). A lens's zoom there is that base times `Lens.zoomFactor`.
3. **No frame is missed.** Across 44 locked transitions the longest gap between frames was one frame, 0 drops. To the wide lens the next frame already has the new framing (the ultra wide cropped), and the wide lens's first frame is captured about 255 to 262 ms after the call at 30 fps, 123 ms at 60. To the ultra wide: 62 to 70 ms at 30 fps, 31 ms at 60. Today's input swap in the same harness: call 205 to 236 ms, picture frozen 233 to 254 ms.
4. **The zoom range lags the lock.** After locking to the ultra wide lens, `minAvailableVideoZoomFactor` took 6 to 33 ms to drop from 2 to 1 on a running session. A zoom of 1.0 or more below that minimum is clamped to it (AVCaptureDevice.h, `minAvailableVideoZoomFactor`), so zoom 1 set too early silently stays 2: the ultra wide lens cropped to the wide lens's framing. Only a zoom below 1.0 or above the format's `videoMaxZoomFactor` raises. Whether the range moves at all while the session is stopped was not measured. (Corrected while building: this first said a zoom below the range raises.)
5. **Custom exposure is refused there.** On the combined camera `activeFormat.supportsExposureModeCustom(lensAperture:duration:iso:)` is false in every form, automatic or locked to either lens, though `isExposureModeSupported(.custom)` is true. The same question on both single cameras is true and the exposure was applied. `CameraSession.applyManual` already asks the format (`CameraSession+Manual.swift:37`), so an exposure that reaches it on the combined camera throws `.notSupported`.
6. **Locked white balance and a locked lens position work there** and held across a lens change. Decision 2A resets them on a lens tap anyway.
7. **The movie output replaces the lock while it records** unless `isPrimaryConstituentDeviceSwitchingBehaviorForRecordingEnabled` is false (AVCaptureFileOutput.h:540; measured: with the default the active behaviour while recording was "restricted", with it off it stayed "locked" and a 4K 30 HLG HEVC clip across four lens changes had 0 frames missing).
8. **What the combined camera records.** Every one of its 51 formats exists on both single back cameras with the same movie codecs (probe of 2026-11-10); its rates stop at 60 fps. On the photo preset it offers no RAW and photos only to 5712x4284, so photo mode never uses it. The 10-bit `x420` HLG data output runs on it at 4K 30 and 60.
9. **Today a lens change is always a configure behind the blur**, 1x to 2x included: `VideoOption` carries `lensID`, so `previous.video != next.video` in `ViewfinderChange.pausesPicture` (`OpenCam/App/ViewfinderChange.swift:16-24`). The configure also returns every manual control to automatic (`CameraModel.swift:705`, `CameraSession.swift:170`).
10. **The saved start is adopted only when it equals the resolved configuration as a whole** (`CameraModel+Launch.swift:44-52`). A start saved before this change has no `combined` and is released once ("differs"), then configured as today; the next confirmation saves one that matches.

## Global Constraints

- Branch `feat/fast-lens-switch` from `feat/recorder` (5c90a8e). The camera core constraints apply: strict Swift 6 concurrency, no force unwraps or `try!`, one type per file, errors as `[Module:Function] Description — {context}`, no `@unchecked Sendable`, `nonisolated(unsafe)` or `@preconcurrency import`, no `Any` in our APIs, conventional commits, no attribution lines.
- Risk rule: a configuration with `combined == nil` is configured exactly as today. Everything new is reached only through a configuration whose `combined` is set.
- The capability cache, `CaptureCapabilities.currentScanVersion` (3) and the scan are untouched. The combined camera is read at launch and held in memory.
- API facts only from the SDK headers (iPhoneOS27.2) or `docs/research` (git-ignored: cite, never commit). `docs/research` and `.superpowers` are never staged.
- Tests: `OPENCAM_SIM_NAME="OpenCam Dev C" scripts/test.sh [Suite]`. Never another session's simulator.
- Device SDK compile after Task 5: `xcodebuild -project OpenCam.xcodeproj -scheme OpenCam -sdk iphoneos -destination generic/platform=iOS -derivedDataPath .build CODE_SIGNING_ALLOWED=NO build`, expected `** BUILD SUCCEEDED **`, 0 warnings.
- Copy: the one new string is "Not available while recording" (a VoiceOver value). Plain, sentence case, no em dashes.
- Nothing about the phone is claimed as verified beyond the two reports. The rest goes on the device checklist.

## Review Focus

1. **A lens button ends on the wrong lens or zoom** (a tap from 1x to 0.5x sets zoom 1 while the range still starts at 2, and the camera clamps it to 2). Device only: `settleZoom` sets a zoom only inside `minAvailableVideoZoomFactor...maxAvailableVideoZoomFactor`, waiting for the range (Task 5); pinned on the phone by the checklist's rapid lens taps.
2. **Manual shutter or ISO is lost, or the camera bounces, with no lens tap:** after a recording, a look change or a Library visit the model must not move a manual exposure back to the combined camera. Pinned by `CameraModelCombinedCameraTests.aConfigureRequestWithNothingChangedKeepsTheManualExposure` (Task 4).
3. **The model and the session disagree about the camera:** a lens tap the model thinks is a zoom but the session swaps the input for, or the reverse. Both read `SessionConfiguration.changesOnlyLens(from:)`; pinned by `ViewfinderChangeTests.aLensChangeInsideTheCombinedCameraDoesNotBlur` and `everyOtherChangeOnTheCombinedCameraStillBlurs` (Task 2).
4. **A lens or option the combined camera cannot serve is sent to it:** a front lens, 120 fps, photo mode. Pinned by `CombinedCameraTests` (Task 1) and `CameraModelCombinedCameraTests.aFrontLensLeavesTheCombinedCameraBehindTheBlur` (Task 4).
5. **An old saved start** (no `combined`) decodes and is replaced, not adopted on the wrong camera. Pinned by `SavedStartTests.aStartSavedBeforeTheCombinedCameraDecodesWithoutOne` (Task 2).

---

### Task 1: The combined camera as plain data

**Files:**
- Create: `OpenCam/Capability/CombinedFormat.swift`, `OpenCam/Capability/CombinedLens.swift`, `OpenCam/Capability/CombinedCamera.swift`
- Test: `OpenCamTests/CombinedCameraTests.swift`

**Interfaces:**
- Consumes: `Lens`, `CaptureMode`, `VideoOption`, `ColourMode.captureColorSpaceRawValue`, `Resolution.width/height`.
- Produces:

```swift
/// One video format of the combined back camera.
nonisolated struct CombinedFormat: Sendable, Equatable {
    let width: Int
    let height: Int
    /// `AVCaptureColorSpace` raw values.
    let colourSpaces: [Int]
    let frameRateRanges: [ClosedRange<Double>]
    let maxZoomFactor: Double
}

/// How the combined back camera shows one lens: the camera to attach and the zoom on it.
nonisolated struct CombinedLens: Codable, Sendable, Equatable {
    let deviceUniqueID: String
    let zoomFactor: Double
}

/// The back camera that holds several lenses and changes between them without a new camera input.
nonisolated struct CombinedCamera: Sendable, Equatable {
    let deviceUniqueID: String
    /// The zoom at which each of its cameras takes over, by that camera's unique ID: 1 for the first, then the switch-over factors.
    let baseZoomByDeviceID: [String: Double]
    let formats: [CombinedFormat]

    /// Nil unless this camera can record `video` through `lens`: video mode, a lens it holds, and a format with the option's
    /// size, colour space and frame rate (the 0.05 tolerance `StandardFrameRates.collapse` uses) whose zoom reaches the lens's.
    func lens(for lens: Lens, mode: CaptureMode, video: VideoOption?) -> CombinedLens?
}
```

- [ ] **Step 1: Write the failing tests** in `CombinedCameraTests.swift` (suite `CombinedCameraTests`). Build the camera once:

```swift
static let camera = CombinedCamera(deviceUniqueID: "dual", baseZoomByDeviceID: ["ultra": 1, "wide": 2], formats: [
    CombinedFormat(width: 3840, height: 2160, colourSpaces: [0, 1], frameRateRanges: [1...60], maxZoomFactor: 129.125),
    CombinedFormat(width: 3840, height: 2160, colourSpaces: [2], frameRateRanges: [1...60], maxZoomFactor: 129.125),
    CombinedFormat(width: 1920, height: 1080, colourSpaces: [0], frameRateRanges: [1...29.97], maxZoomFactor: 3),
])
```

with lenses `ultra` (device "ultra", zoom 1), `wide` (device "wide", zoom 1), `wide@2` (device "wide", zoom 2), `outer` (device "outer", zoom 1) and a helper `option(_ lens:, width:, height:, rate:, colour:)` (HEVC "High"). Tests and assertions:
  - `eachBackLensGetsItsZoom`: 4K 30 Rec. 709 gives `CombinedLens(deviceUniqueID: "dual", zoomFactor: 1)` for `ultra`, `2` for `wide`, `4` for `wide@2`.
  - `hlgAndLogUseTheHLGFormat`: 4K 60 `.hlg` and `.log` on `wide` are served; 4K 60 `.appleLog` is nil.
  - `aRateAboveTheFormatsIsNotServed`: 4K 120 on `wide` is nil; 1080p 30 on `wide` is served (29.97 within 0.05 of 30); 1080p 60 is nil.
  - `aLensItDoesNotHoldIsNotServed`: any option on `outer` is nil.
  - `photoModeAndNoOptionAreNotServed`: `mode: .photo` is nil; `video: nil` is nil.
  - `aZoomPastTheFormatIsNotServed`: 1080p 30 on `wide@2` (zoom 4 > 3) is nil.
- [ ] **Step 2: Run** `OPENCAM_SIM_NAME="OpenCam Dev C" scripts/test.sh CombinedCameraTests`. Expected: fails to compile (`CombinedCamera` undefined).
- [ ] **Step 3: Implement** the three types, one per file.
- [ ] **Step 4: Run** the same command. Expected: 6 tests pass.
- [ ] **Step 5: Commit** `feat: describe the combined back camera as plain data`.

### Task 2: The configuration names its camera

**Files:**
- Modify: `OpenCam/Capture/SessionConfiguration.swift`, `OpenCam/App/ViewfinderChange.swift`
- Test: `OpenCamTests/ViewfinderChangeTests.swift`, `OpenCamTests/SavedStartTests.swift`

**Interfaces:**
- Consumes: `CombinedLens` (Task 1).
- Produces, on `SessionConfiguration`:

```swift
/// Set when the combined back camera records this configuration; nil is the lens's own camera, as always.
var combined: CombinedLens?
/// The camera the session attaches.
var cameraUniqueID: String { combined?.deviceUniqueID ?? lens.deviceUniqueID }
/// The zoom on that camera.
var zoomFactor: Double { combined?.zoomFactor ?? lens.zoomFactor }
/// True when both are video on the same combined camera with the same codec, size, rate, colour, sound, frame feed and
/// recorder, so at most the lens differs. `photo` and each option's `lensID` are not compared: video ignores the first and
/// the second only says which lens lists the option.
func changesOnlyLens(from previous: SessionConfiguration) -> Bool
```

`combined` is decoded with `decodeIfPresent` (nil when absent), and is a trailing `combined: CombinedLens? = nil` parameter of `init(lens:...)` and of `make(lens:...)`.

`ViewfinderChange.pausesPicture(from:to:)` becomes: false when `previous` is nil; false when `next.changesOnlyLens(from: previous)`; otherwise today's rule with `previous.cameraUniqueID != next.cameraUniqueID` in place of the lens device comparison. Its doc comment says so.

- [ ] **Step 1: Write the failing tests.**
  - `ViewfinderChangeTests.aLensChangeInsideTheCombinedCameraDoesNotBlur`: from the fixture model's configuration (video), make `onUltra`, `onWide`, `onZoomed`, each with its lens, `video` rebuilt with that lens's `lensID` (same codec, resolution, frame rate, colour), `photo` set to that lens's photo option, and `combined = CombinedLens(deviceUniqueID: "fixture-dual", zoomFactor: 1 / 2 / 4)`. Expect `!pausesPicture` for every ordered pair, and `changesOnlyLens` true for every pair.
  - `ViewfinderChangeTests.everyOtherChangeOnTheCombinedCameraStillBlurs`: from `onWide` above, each of these pauses and is not `changesOnlyLens`: `combined = nil` (same lens, own camera); `combined` on another device ID; `mode = .photo`; another frame rate; another colour; `includesAudio` toggled; `needsFrames` toggled. `recorder = .writer` alone is not `changesOnlyLens` (today's rule does not compare the recorder, which only ever changes with the option, so no pause is asserted for it). And from a configuration with `combined == nil` to `onWide`: pauses.
  - `SavedStartTests.aStartSavedBeforeTheCombinedCameraDecodesWithoutOne`: encode a `SessionConfiguration`, remove the `combined` key from the JSON object if present, decode: `combined == nil`; and a configuration with `combined` set round-trips equal.
- [ ] **Step 2: Run** `scripts/test.sh ViewfinderChangeTests` and `scripts/test.sh SavedStartTests` (with `OPENCAM_SIM_NAME`). Expected: fail to compile.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** both suites. Expected: pass, the existing `aZoomOnlyChangeDoesNotBlur` included.
- [ ] **Step 5: Commit** `feat: let a session configuration name the combined camera`.

### Task 3: Read the combined camera at launch

**Files:**
- Create: `OpenCam/Capture/CombinedCameraDiscovery.swift`
- Modify: `OpenCam/Capture/CapabilitySource.swift`, `OpenCam/App/CameraModel.swift` (`sessionConfiguration`, a stored `combinedCamera`), `OpenCam/App/CameraModel+Launch.swift` (`discoverLenses(with:)`)
- Test: `OpenCamTests/CameraModelCombinedCameraTests.swift` (new)

**Interfaces:**
- Consumes: `CombinedCamera.lens(for:mode:video:)`, `SessionConfiguration.make(... combined:)`.
- Produces:
  - `nonisolated enum CombinedCameraDiscovery { static func camera() -> CombinedCamera? }`: the first `.builtInDualWideCamera` at the back, nil unless `isPrimaryConstituentDeviceSwitchingBehaviorLockedWithDeviceSupported` and `constituentDevices.count == virtualDeviceSwitchOverVideoZoomFactors.count + 1`; base zooms are `[1] + switchOverFactors` zipped with `constituentDevices` in order; one `CombinedFormat` per `device.formats` entry (`supportedColorSpaces` raw values, `videoSupportedFrameRateRanges` as `min...max`, `videoMaxZoomFactor`). Property reads only, no session.
  - `CapabilitySource.combinedCamera: @Sendable () -> CombinedCamera?`, a `var` with the default `{ nil }` so existing initialisers compile; `.device` passes `{ CombinedCameraDiscovery.camera() }`.
  - `CameraModel.combinedCamera: CombinedCamera?` (`@ObservationIgnored`, internal `var`), set in `startCamera` from the same off-main call that discovers the lenses (the helper returns both).
  - `CameraModel.sessionConfiguration` passes `combined: manual.exposure == .automatic ? combinedCamera?.lens(for: currentLens, mode: mode, video: currentVideoOption) : nil`.

- [ ] **Step 1: Write the failing tests** in the new suite `CameraModelCombinedCameraTests`, with a helper like `ViewfinderChangeTests.deviceModel` that sets `model.combinedCamera` before `attachSession`:

```swift
static let combined = CombinedCamera(deviceUniqueID: "fixture-dual", baseZoomByDeviceID: ["fixture-ultraWide": 1, "fixture-wide": 2],
    formats: [3840, 1920].flatMap { width in  // 4K and 1080p, every colour space, to 60 fps
        [CombinedFormat(width: width, height: width * 9 / 16, colourSpaces: [0, 1, 2], frameRateRanges: [1...60], maxZoomFactor: 100)] })
```

  - `videoOnABackLensNamesTheCombinedCamera`: on `wide` in video, `sessionConfiguration?.combined == CombinedLens(deviceUniqueID: "fixture-dual", zoomFactor: 2)`; after `selectLens("ultraWide")` zoom 1; after `selectLens("wide@2")` zoom 4.
  - `photoModeAndFrontLensesKeepTheirOwnCamera`: `mode = .photo` gives `combined == nil`; video on `outer` gives nil.
  - `aSourceWithACombinedCameraHandsItToTheModel`: a `CapabilitySource` whose `combinedCamera` returns `Self.combined`, run through `startCamera(on:savedStart:)` as `CameraLaunchTests` does: `model.combinedCamera == Self.combined` and the fake's first applied configuration has `combined` set.
- [ ] **Step 2: Run** `scripts/test.sh CameraModelCombinedCameraTests`. Expected: fails to compile.
- [ ] **Step 3: Implement.** If the fixture's selected option is not 4K or 1080p at up to 60 fps, the test selects one that is.
- [ ] **Step 4: Run** the suite, then the whole suite (`scripts/test.sh`). Expected: all pass; with `combinedCamera == nil` nothing else changes.
- [ ] **Step 5: Commit** `feat: read the combined back camera at launch`.

### Task 4: The model: lens taps without the blur, manual exposure on the lens's own camera

**Files:**
- Modify: `OpenCam/App/CameraModel.swift` (`enqueueConfigure`, `saveStart`), `OpenCam/App/CameraModel+Manual.swift`, `OpenCam/App/CameraModel+Recording.swift` (`recordingBegan`)
- Test: `OpenCamTests/CameraModelCombinedCameraTests.swift`

**Interfaces:**
- Consumes: Tasks 1 to 3.
- Produces:
  - `enqueueConfigure(keepsManual: Bool = false)`. The body changes only as follows, in this order: the guard reads `sessionConfiguration` as `wanted` and compares it with `requestedConfiguration` as today; then `if keepsManual { manualGeneration += 1; appliedManual = .automatic } else { resetManual() }`; then `sessionConfiguration` is read again as `configuration` (after the reset exposure is automatic, so the combined camera may serve the selection) and everything after uses it. In the task: a failed configure with `keepsManual` calls `resetManual()` before `configureFailed`; after `refreshReadouts`, `if keepsManual, generation == configureGeneration { reapplyAllManual() }`.
  - In `CameraModel+Manual.swift`: `setControl` calls `sendManual()` only when this returns false:

```swift
/// Shutter and ISO cannot be set on the combined camera (measured 2026-11-16), so the first one set by hand moves the
/// session to the lens's own camera, behind the blur; the values are sent once it is attached.
private func movesToOwnCameraForExposure() -> Bool {
    guard requestedConfiguration?.combined != nil, manual.exposure != .automatic else { return false }
    return enqueueConfigure(keepsManual: true) != nil
}

/// Shutter and ISO need the lens's own camera, and a recording cannot change camera: on the combined camera they wait
/// for the clip to end.
func waitsForRecordingToEnd(_ control: ManualControl) -> Bool {
    isRecording && manual.exposure == .automatic && requestedConfiguration?.combined != nil && (control == .shutter || control == .iso)
}
```

  `waitsForRecordingToEnd` makes `readout(for:)` unavailable and dimmed with the accessibility value "Not available while recording", and is a guard in `toggleControl`, `setControl` and `openSlider`. `recordingBegan` closes the open control when it now waits.
  - `saveStart` saves the configuration as a launch would configure it, exposure automatic: `configuration.combined = combinedCamera?.lens(for: configuration.lens, mode: configuration.mode, video: configuration.video)`.

- [ ] **Step 1: Write the failing tests** (same suite and helper; `fake` is the `FakeSessionConfigurator`; wait with `model.waitForQueuedConfigures()` and the suite's `eventually` helper for manual applies):
  - `aLensTapInsideTheCombinedCameraDoesNotBlur`: `selectLens("ultraWide")`: `model.isViewfinderChanging` is false right after the call and after the configure; the fake applied one more configuration with `combined?.zoomFactor == 1`; then `selectLens("wide@2")`: zoom 4, still no blur.
  - `aLensTapReturnsTheControlsToAutomatic`: set focus by hand (`setControl(.focus, step:)`), `selectLens("ultraWide")`: `model.manual == .automatic`.
  - `aFrontLensLeavesTheCombinedCameraBehindTheBlur`: `selectLens("outer")`: `isViewfinderChanging` true at once; applied configuration has `combined == nil`; back to `wide`: blur again, `combined` set.
  - `theFirstManualShutterMovesToTheLensesOwnCamera`: `setControl(.shutter, step: 3)`: `isViewfinderChanging` true at once; after the configure the fake's last applied configuration has the same lens and `combined == nil`; the fake's last manual apply has `reapplyingAll == true` and a manual exposure; `model.manual.exposure != .automatic`.
  - `aLensTapAfterAManualExposureReturnsToTheCombinedCamera`: after the test above's steps, `selectLens("ultraWide")`: one more configuration, `combined?.zoomFactor == 1`, `model.manual == .automatic`.
  - `aConfigureRequestWithNothingChangedKeepsTheManualExposure`: after the manual shutter move, `model.enqueueConfigure()` returns nil, the fake's applied count is unchanged and `model.manual.exposure != .automatic`.
  - `shutterAndISOWaitWhileRecordingOnTheCombinedCamera`: with `model.isRecording = true` on `wide`: `readout(for: .shutter).isAvailable == false`, its `accessibilityValue == "Not available while recording"`, `setControl(.iso, step: 2)` changes nothing and applies nothing; `readout(for: .focus).isAvailable == true`.
  - `theSavedStartIsTheAutomaticCamera`: after the manual shutter move, `model.saveStart(...)` with the last working pair, then `SavedStart.load(from:)`: its configuration's `combined?.zoomFactor == 2`.
  - `aFailedMoveReturnsExposureToAutomatic`: the fake fails the lens (`setFailingLensIDs(["wide"])`) before `setControl(.shutter, ...)`: afterwards `model.manual.exposure == .automatic` and `requestedConfiguration?.combined != nil`.
- [ ] **Step 2: Run** `scripts/test.sh CameraModelCombinedCameraTests`. Expected: the new tests fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the suite, then the whole suite. Expected: all pass.
- [ ] **Step 5: Commit** `feat: change lens on the combined camera without the blur`.

### Task 5: The session: attach, lock to the lens, change lens without a configure

**Files:**
- Modify: `OpenCam/Capture/CameraSession.swift`, `OpenCam/Support/TimingJournal.swift`
- Test: `OpenCamTests/TimingJournalTests.swift` (new; nothing tests the journal's texts yet)

**Interfaces:**
- Consumes: `SessionConfiguration.cameraUniqueID`, `zoomFactor`, `combined`, `changesOnlyLens(from:)`.
- Produces: `TimingJournal.describeLensChange(to:from:) -> String` returning `"lens 0.5x to 1x on the combined camera"` (the lenses' labels), and `TimingJournal.lensChange(to:from:since:)`, which always writes `[timing] <that text> <ms> ms` to the error journal: the line is the proof on the phone that no configure ran.

The session code cannot run in the Simulator, so it is given whole. In `CameraSession.swift`:

1. `apply(_:)`: the device is `AVCaptureDevice(uniqueID: configuration.cameraUniqueID)`; after `preparePixelFormat`, call `settleZoom(configuration, on: device)`.
2. `configureSession`: after `attachMovieOutput`, `if device.isVirtualDevice, wantedOutputs.contains(.movie) { recorder.output.isPrimaryConstituentDeviceSwitchingBehaviorForRecordingEnabled = false }`, with a comment citing "Read first" 7.
3. `applyFormat`: `zoom` is `CGFloat(configuration.zoomFactor)`; the last line becomes `if configuration.combined != nil { try lockLens(configuration, on: device) } else { device.videoZoomFactor = zoom }`. `applyPresetPhoto` is untouched (photo never has `combined`).
4. `configure(_:)`: inside the `do`, `if let previous = lastWorkingConfiguration, canChangeLensOnly(to: configuration, from: previous) { try changeLens(configuration, from: previous) } else { try apply(configuration); installSystemControls(...) }`, then `lastWorkingConfiguration = configuration` as today. The catch is unchanged: it restores with the full `apply`.
5. `start()`, after `startRunning`, and `restartAfterMediaServicesReset()`, before `resetManual()`: `restoreLens()`.
6. New members:

```swift
/// A lens button inside the combined camera is a lock and a zoom when the session runs it already and nothing else differs.
private func canChangeLensOnly(to configuration: SessionConfiguration, from previous: SessionConfiguration) -> Bool {
    session.isRunning && videoInput?.device.uniqueID == configuration.combined?.deviceUniqueID && configuration.changesOnlyLens(from: previous)
}

/// Changes lens with no session configuration, so no frame is missed (measured 2026-11-16: the longest gap is one frame; the
/// wide lens's first frame comes about 260 ms after the call at 30 fps, the ultra wide's about 70 ms). The camera returns
/// to automatic, as after every configure.
private func changeLens(_ configuration: SessionConfiguration, from previous: SessionConfiguration) throws(CameraSessionError) {
    guard let device = videoInput?.device else { throw .deviceMissing(lensID: configuration.lens.id) }
    let start = ContinuousClock.now
    do {
        try device.lockForConfiguration()
    } catch {
        throw .lockFailed(reason: String(describing: error))
    }
    do throws(CameraSessionError) {
        try lockLens(configuration, on: device)
    } catch {
        device.unlockForConfiguration()
        throw error
    }
    device.unlockForConfiguration()
    settleZoom(configuration, on: device)
    resetManual()
    TimingJournal.lensChange(to: configuration, from: previous, since: start)
}

/// Caller holds the configuration lock. Locks the combined camera to the lens's own camera, so the button decides the lens
/// and never the scene: with the default switching the camera kept the ultra wide lens at 1x in four of five sessions
/// (measured 2026-11-16). The lock moves the zoom into the lens's range by itself; the zoom asked for is set here when the
/// range already holds it, else by `settleZoom`.
private func lockLens(_ configuration: SessionConfiguration, on device: AVCaptureDevice) throws(CameraSessionError) {
    guard device.isPrimaryConstituentDeviceSwitchingBehaviorLockedWithDeviceSupported,
          let lensDevice = device.constituentDevices.first(where: { $0.uniqueID == configuration.lens.deviceUniqueID }) else {
        throw .deviceMissing(lensID: configuration.lens.id)
    }
    if device.primaryConstituentDeviceSwitchingBehavior != .locked || device.activePrimaryConstituent?.uniqueID != lensDevice.uniqueID {
        device.setPrimaryConstituentDeviceSwitchingBehaviorLockedWith(lensDevice)
    }
    let zoom = CGFloat(configuration.zoomFactor)
    if zoom >= device.minAvailableVideoZoomFactor, zoom <= device.maxAvailableVideoZoomFactor {
        device.videoZoomFactor = zoom
    }
}

/// Sets the configuration's zoom on the combined camera when the lock left it elsewhere. After a lock to the ultra wide lens
/// the zoom range took 6 to 33 ms to open below the wide lens's (measured 2026-11-16), and a zoom outside the range raises an
/// exception Swift cannot catch (AVCaptureDevice.h, `videoZoomFactor`). So this waits for the range, at most a quarter
/// second and only while the session runs, and otherwise leaves the zoom where the lock put it; `restoreLens` tries again
/// once the session has started.
private func settleZoom(_ configuration: SessionConfiguration, on device: AVCaptureDevice) {
    guard configuration.combined != nil else { return }
    let zoom = CGFloat(configuration.zoomFactor)
    guard device.videoZoomFactor != zoom else { return }
    let isHeld = { zoom >= device.minAvailableVideoZoomFactor && zoom <= device.maxAvailableVideoZoomFactor }
    let deadline = ContinuousClock.now + .milliseconds(250)
    while session.isRunning, !isHeld(), ContinuousClock.now < deadline {
        Thread.sleep(forTimeInterval: 0.002)
    }
    guard isHeld() else {
        Self.logger.error("[CameraSession:settleZoom] The zoom range does not hold the lens's zoom — {lens: \(configuration.lens.id, privacy: .public), zoom: \(Double(zoom)), min: \(Double(device.minAvailableVideoZoomFactor)), running: \(self.session.isRunning)}")
        return
    }
    do {
        try device.lockForConfiguration()
    } catch {
        Self.logger.error("[CameraSession:settleZoom] Cannot lock the camera for configuration — {lens: \(configuration.lens.id, privacy: .public), reason: \(String(describing: error), privacy: .public)}")
        return
    }
    device.videoZoomFactor = zoom
    device.unlockForConfiguration()
}

/// Puts the applied configuration's lens back on the combined camera: after a start, when the zoom could not be set before
/// the session ran, and after a restart, when the camera may have come back unlocked.
private func restoreLens() {
    guard let applied = lastWorkingConfiguration, applied.combined != nil, let device = videoInput?.device else { return }
    do {
        try device.lockForConfiguration()
    } catch {
        Self.logger.error("[CameraSession:restoreLens] Cannot lock the camera for configuration — {lens: \(applied.lens.id, privacy: .public), reason: \(String(describing: error), privacy: .public)}")
        return
    }
    do throws(CameraSessionError) {
        try lockLens(applied, on: device)
    } catch {
        Self.logger.error("\(error.description, privacy: .public)")
    }
    device.unlockForConfiguration()
    settleZoom(applied, on: device)
}
```

- [ ] **Step 1: Write the failing test** `describesALensChangeOnTheCombinedCamera`: for the fixture's `ultraWide` and `wide` lenses, `TimingJournal.describeLensChange(to:from:) == "lens \(ultra.label) to \(wide.label) on the combined camera"`.
- [ ] **Step 2: Run** that suite. Expected: fails to compile.
- [ ] **Step 3: Implement** `TimingJournal` and the session changes above. If `CameraSession.swift` passes the repo's file-length habit, the new members go in `OpenCam/Capture/CameraSession+Lens.swift` with the access levels that needs.
- [ ] **Step 4: Run** the whole suite and the device SDK compile (Global Constraints). Expected: all tests pass; `** BUILD SUCCEEDED **`, 0 warnings.
- [ ] **Step 5: Commit** `feat: lock the combined camera to the lens and change lens without a configure`.

### Task 6: The device checklist

**Files:**
- Modify: `docs/device-checklist.md` (a new section "Fast lens switch (combined back camera)")

- [ ] **Step 1: Add the section**, each line a checkbox, covering: the journal shows `[timing] lens ... on the combined camera` lines and no `configure ... (lens...)` line for taps between 0.5x, 1x and 2x in video at 30 and 60 fps (HEVC and ProRes, Rec. 709 and HLG); no blur and no frozen picture on those taps, and how the 0.5x to 1x hand-over looks; twenty fast taps around 0.5x, 1x, 2x with no crash; 1x on the combined camera against 1x in photo mode (framing, sharpness); a tap to a front lens and back blurs once each way; 120 fps options blur as before; the first manual shutter or ISO blurs once and takes the value, a lens tap after it returns the controls to automatic; while recording with exposure automatic, shutter and ISO are dimmed and VoiceOver says "Not available while recording", white balance, focus and EV still work; a system clip and a writer clip recorded on each of 0.5x, 1x, 2x play upright with no missing frames; the lens does not change by itself mid clip with a hand held 5 cm from the lens; the Camera Control zoom on the combined camera; launch with a saved start on 1x, 0.5x and 2x shows the right lens and the journal's launch line; a Library visit and a phone call return to the right lens; heat and battery over ten minutes on 1x against the build before.
- [ ] **Step 2: Commit** `docs: add the fast lens switch device checks`.

## Changed while building

- `settleZoom`'s comment follows the corrected "Read first" 4, and it checks the range once more after taking the configuration lock (Task 5 review).
- `confirmLens(_:on:)` replaces the bare `settleZoom` call after a configure's commits and is what `restoreLens` runs: it reads the lock and the zoom back from the camera and puts them right, because whether a new format keeps the lock was not measured.
- A lens-only change writes only its `[timing] lens ...` line: the `configure` line is skipped for it even when the change took over 100 ms (Task 5 review).
- The movie output's recording switching flag is gated on `configuration.combined != nil`, not on the device being a combined one.
- `enqueueConfigure` returns nil when the configuration read after the reset is what the session already runs, and a failed move to a lens's own camera resets the controls only when no newer configure overtook it (Task 4 review).
- The open shutter or ISO slider is closed in `startRecording()` where `isRecording` becomes true, not in `recordingBegan`, which runs only after the awaited start.
- The new session members live in `OpenCam/Capture/CameraSession+Lens.swift`.
