# OpenCam Camera Basics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Paths are relative to the worktree root, `/Users/tannerpham/CS Projects/DuoCam/.claude/worktrees/feat+camera-core`.

**Goal:** Tapping a clip in the Library plays it with its recording details, share and delete; in the viewfinder a tap focuses and exposes there, a long press locks both, and a pinch zooms within the current lens.

**Architecture:** Three slices, each all new files except named insertion points. Clip playback is a Library navigation destination (`ClipScreen`) around AVKit's `VideoPlayer`, with a pure `ClipInfo` built from the sidecar. Focus: a pure `PreviewGeometry` turns a viewfinder point into a sensor point, a pure `FocusPlan` decides what the device may be asked given what is set by hand, a pure `FocusTapState` decides the marker and the lock capsule; `CameraSession+Focus.swift` executes plans on the actor and watches the subject area. Pinch: a pure `PinchZoom` holds the lens-relative factor, its clamp, its label and its reset rule; the session keeps the factor and every place that sets the zoom asks it for the target, so configure, start, restart and the lens branch's `confirmLens` all re-apply it. Taps, holds and pinches are UIKit recognizers through `UIGestureRecognizerRepresentable` on one overlay view.

**Tech Stack:** Swift 6 (MainActor default isolation), SwiftUI, AVKit, AVFoundation, Swift Testing. No dependencies.

**Spec:** The owner chose "camera basics": "Tap to focus and expose, pinch zoom, clip playback. These are what you will miss first when actually shooting." The controller's briefs (2026-11-18), with these findings from the code and the SDK:

1. **Tapping a clip already plays it.** `LibraryView.swift:138-139` sets `previewURL` and `.quickLookPreview` (`:60`) shows the system Quick Look, which plays the MOV and has its own share button. What is missing is the recording details and delete. This plan replaces Quick Look with `ClipScreen` (Q1).
2. **The Library has no share action.** Share exists only in the editor's Export (`EditorView.swift:35-37`, `ShareSheet` for a rendered temporary file). Delete exists only in Select mode (`LibrarySelectionBar`, `LibraryView.swift:230-245`). `ClipScreen` reuses the delete dialog and `LibraryStore.delete(_:)`; share is `ShareLink` on the file that already exists (Q3).
3. **`-seedSamples on` seeds three JPEGs and no clip** (`SampleSeeder.swift:14-19`). A new `-seedClip on` writes a 3 s H.264 clip with a real sidecar in the Simulator.
4. **The viewfinder takes no gesture today.** `ViewfinderArea` has none; the only drag is `StepSlider`'s, inside `PictureSliderColumn`, an overlay of `CameraLayout` drawn above the layouts (`CameraLayout.swift:30-37`), so it keeps its own touches. The status screens' Try again (`ViewfinderArea.swift:52-58`) must stay tappable: the gesture layer exists only while `hasCamera`.
5. **The preview layer's converter does not promise rotation or mirroring.** `AVCaptureVideoPreviewLayer.h:148` says `captureDevicePointOfInterestForPoint:` "takes frameSize and videoGravity into consideration"; only the metadata converter at `:208` names orientation and mirroring. The app already fixes the display rule in `FrameOrientation.swift:5-8`: turn by the preview's angle, then flip horizontally for a front camera. `PreviewGeometry` is the exact inverse of that rule, and on the phone each tap journals any disagreement with the layer's converter (Q4).
6. **The fast lens switch is merged into this branch** (`f7acf14`, merge of `origin/feat/fast-lens-switch` at `edc7e39`). Zoom is set in four places: `CameraSession.applyFormat` (`CameraSession.swift:536`, set at `:551` on a lens's own camera), `applyPresetPhoto` (`:246-251`, photo preset), `lockLens` (`CameraSession+Lens.swift:51-53`) and `settleZoom` (`:65`, `:85`). `restoreLens` (`:124-127`) runs after `start()` and after a media-services restart, but `confirmLens` returns early on a lens's own camera, so today a restart re-applies nothing there. Pinch reuses all of these by changing only where the number comes from.
7. **The Duo's front cameras have no focus slider** (device checklist 8, "Both front lenses offer no focus slider"), so the exposure-only fallback is the normal case there, not an edge case.

**Header facts** (`$(xcrun --sdk iphoneos --show-sdk-path)`, iPhoneOS27.2; `AVCaptureDevice.h` unless named):

- F1 `:1240`, `:1248`: `focusPointOfInterest` needs `isFocusPointOfInterestSupported`; (0,0) top left, (1,1) bottom right; setting it "does not initiate a focus operation", set `focusMode` after. `:1478`, `:1486`: the same for exposure.
- F2 `:1163-1171`: `.autoFocus` focuses once, then becomes `.locked`. `:1427-1428`: `.autoExpose` exposes once, then becomes `.locked`. `:1210`, `:1458`: each mode behind `isFocusModeSupported` / `isExposureModeSupported`. No call used here is deprecated at iOS 27 (no `API_DEPRECATED` in `:1195-1600`).
- F3 `:44-51`, `:2017-2024`: `subjectAreaDidChangeNotification` is sent only while `isSubjectAreaChangeMonitoringEnabled`, which needs the configuration lock.
- F4 `:1264`, `:1502`: a new `activeFormat` reverts the points of interest to their defaults. A lens change on the combined camera keeps the format, so the session resets the point itself.
- F5 `AVCaptureVideoPreviewLayer.h:148-150`: the device point is "on an unrotated picture". `AVCaptureSession.h:1075`: rotation angles are 0, 90, 180, 270 only. `:1050`: mirroring flips about the vertical axis.
- F6 `:2074`, `:2080`: `videoZoomFactor` outside the acceptable range raises `NSRangeException`; setting it cancels a ramp. `:2092-2098`: `ramp(toVideoZoomFactor:withRate:)` scales by `pow(2, rate * time)`, rate changes are smoothed, needs the configuration lock. `:3455-3462`: `videoZoomFactorUpscaleThreshold`.
- F7 `:2979-2990` (iOS 27): continuous autofocus tracking exists, needs a metadata output; not used (see "Not in this plan").
- F8 `_AVKit_SwiftUI.framework/.../arm64e-apple-ios.swiftinterface:39`, `:49`: `VideoPlayer(player: AVPlayer?)`, iOS 14, not deprecated. `SwiftUI.swiftinterface:28609`: `UIGestureRecognizerRepresentable`; its converter gives `localLocation`.

## Global Constraints

- Branch `feat/camera-basics`, as it is now (fast lens switch merged). House rules: strict Swift 6, one type per file, no force unwraps or `try!`, no `@unchecked Sendable`, `nonisolated(unsafe)` or `@preconcurrency import`, no `Any` in our APIs, errors as `[Module:Function] Description — {context}`, 0 warnings in Debug and Release, conventional commits with no attribution lines, `docs/research` and `.superpowers` never staged.
- Risk rule: with no tap and no pinch the camera behaves exactly as today. No session call is added to any path a gesture did not start; the pinch factor 1 gives every zoom setter today's number. A tap or a pinch never configures the session, never raises `isViewfinderChanging`, and never changes `ManualSettings`.
- New behaviour lives in new files. The only edits to existing files are the insertion points named in each task; every edit to code the fast lens switch added or changed is listed under "Touch points in the lens branch's code" below and kept to one line each.
- `.onCameraCaptureEvent` stays on the NavigationStack's content directly after the strip modifier (`CameraRootView.swift:34-41`); `CameraRootView` is not edited.
- Copy in the tasks is final: plain, sentence case, no em dashes. Reuse `Theme`, `LibraryBadge`'s glass capsule, the `DroppedFramesBadge` overlay pattern and the strip's own text.
- Tests: `scripts/test.sh <Suite>`; whole suite `scripts/test.sh`, green at the end of every task. Device compile at the end of Tasks 4, 7 and 9: `xcodebuild -project OpenCam.xcodeproj -scheme OpenCam -sdk iphoneos -destination generic/platform=iOS -derivedDataPath .build CODE_SIGNING_ALLOWED=NO build` and the same with `-configuration Release`, 0 warnings.
- Simulator: folded "OpenCam Dev" through `scripts/sim-udid.sh`. Tap checks, portrait and landscape: one action, wait 2 s, `xcrun simctl io "$(scripts/sim-udid.sh)" screenshot --display=1 <file>`, look at the PNG. Screenshots in `docs/screenshots/camera-basics/`, names `basics-…`, launches through `SHOT_DIR=docs/screenshots/camera-basics scripts/shot.sh <name> …`.
- Nothing about the phone is claimed as verified; device checks go in a new section 12 of `docs/device-checklist.md`.

### Touch points in the lens branch's code

| File:line now | Change | Task |
|---|---|---|
| `CameraSession.swift:121` (`appliedManual = nil` in `configure`) | one line after it: `if !PinchZoom.keeps(from: lastWorkingConfiguration, to: configuration) { pinch = 1 }` | 7 |
| `CameraSession.swift:251` (`applyPresetPhoto`) | `device.videoZoomFactor = targetZoom(for: configuration, on: device)` | 7 |
| `CameraSession.swift:551` (`applyFormat`, own camera) | the same | 7 |
| `CameraSession+Lens.swift:51` (`lockLens`) | `let zoom = targetZoom(for: configuration, on: device)` | 7 |
| `CameraSession+Lens.swift:65` (`settleZoom`) | the same | 7 |
| `CameraSession+Lens.swift:126` (`restoreLens`) | one line after `confirmLens`: `restorePinch(applied, on: device)` | 7 |
| `CameraModel.swift:741` (`enqueueConfigure`, after the second `guard`) | one line: `if !PinchZoom.keeps(from: requestedConfiguration, to: configuration) { pinch = 1 }` | 8 |
| `CameraModel+Manual.swift:99`, `:121` (last line of `setControl`, after the lens branch's `movesToOwnCameraForExposure()` line, and of `setAutomatic`) | one line after each: `manualChangedForFocus()` | 5 |

Not touched: `canChangeLensOnly`, `changeLens`, `confirmLens`'s body, `SessionConfiguration`, `CombinedCamera`, `ViewfinderChange`, the base zoom used to pick a format (`CameraSession.swift:536-549`). Other existing files edited (not lens-branch code): `CameraSession.swift:61` (stored properties), `CameraSession+Manual.swift:65`, `CameraModel.swift:72`, `:629`, `SessionConfigurator.swift`, `SimulatedState.swift` (`StoppedSessionStandIn`), `FakeSessionConfigurator.swift` (appended methods only), `PreviewUIView.swift`, `StripControl.swift:32-36`, the three folded layouts, `LibraryView.swift`, `PhotoInfoLine.swift`, `LaunchConfig.swift`, `LibraryCopy.swift`, `docs/device-checklist.md`.

## Review Focus

1. **A gesture-free session changes:** a new call on launch, a zoom setter given a different number with no pinch, a subject-area watch left on. Pinned by `CameraModelFocusTests.withoutAGestureTheSessionHearsNothingNew` (Task 5) and `PinchZoomTests.withNoPinchTheTargetIsTheConfigurationsZoom` (Task 6).
2. **The camera focuses somewhere other than the finger:** a quarter turn the wrong way, a front camera's mirror undone twice, a tap in the letterbox bars sent as a point outside 0...1. Pinned by `PreviewGeometryTests.everyAngleAndMirrorSendsTheCornersToTheSensorsCorners` and `aTapInTheBarsIsNotAPoint` (Task 3).
3. **A tap undoes what was set by hand:** a manual focus or shutter replaced by a point. Pinned by `FocusPlanTests.aManualFocusKeepsFocusAndMovesOnlyExposure` and `bothManualDoesNothing` (Task 3).
4. **The pinch is lost or kept at the wrong time:** a restart, a Library visit or a look toggle dropping it; a lens tap keeping it on the next lens. Pinned by `PinchZoomTests.keepsAcrossALookChangeButNotLensModeOrFormat` (Task 6) and `CameraModelZoomTests.aLensTapResetsThePinchToOne` (Task 8).
5. **A clip with a missing or broken sidecar shows a blank or wrong screen.** Pinned by `ClipInfoTests.aMissingOrUnreadableSidecarSaysSo` (Task 1).

---

### Task 1: Clip details and a sample clip

**Files:** Create `OpenCam/Library/ClipInfo.swift`, `OpenCam/Library/SampleSeeder+Clip.swift`. Modify `OpenCam/Library/LibraryCopy.swift` (append), `OpenCam/App/LaunchConfig.swift` (one property after `var seedsStudyLook`, one parse block after `-seedStudy`). Tests: `OpenCamTests/ClipInfoTests.swift`, `OpenCamTests/SampleClipSeederTests.swift`, `LaunchConfigTests.swift` (one test).

**Interfaces. Consumes:** `ClipSidecar`, `ClipFacts`, `DropFacts`, `VideoCodec.displayName`, `Resolution.named`, `ColourMode.shortName`, `ClipInspector.inspect`, `CaptureStore`, `PhotoInfoRow`. **Produces:**

```swift
nonisolated struct ClipInfo: Sendable, Equatable {
    let summary: String          // "HEVC High · 4K · 30 fps · HLG"; LibraryCopy.noClipDetails without a sidecar
    let rows: [PhotoInfoRow]     // empty without a sidecar
    init(sidecar: ClipSidecar?)
    @concurrent static func load(for item: LibraryItem) async -> ClipInfo   // decodes item.sidecarURL (ISO 8601 dates, as ClipDuration); unreadable: init(sidecar: nil), logged
    static func frameRateText(_ fps: Double) -> String    // 30 "30 fps", 29.97 "29.97 fps", 59.94006 "59.94 fps"
    static func dataRateText(megabitsPerSecond: Double) -> String   // >= 10 "148 Mb/s", else one decimal "6.2 Mb/s"
}
extension SampleSeeder { static func seedClipIfAbsent(_ captures: CaptureStore) async throws(LibraryError) -> Int }
// LaunchConfig: var seedsClip = false   // -seedClip on (honoured in the Simulator only), scripted
// LibraryCopy: static let noClipDetails = "No recording details for this clip.", clipInfoTitle = "Clip info",
//              deleteClipTitle = "Delete this clip?", deleteClipMessage = "The clip and its recording details are removed from OpenCam. This cannot be undone."
```

Rows, in order, present ones only: Codec (`requested.codec.displayName`), Size (`Resolution.named(width:height:)` of `actual`, "4K, 3840 × 2160", or the detail alone when the label is the detail; else `requested.resolution`), Frame rate (`actual.nominalFrameRate`, else `requested.frameRate`), Colour (`actual.colour`, else `requested.colour`), Data rate (`actual` only), Duration (`LibraryCopy.duration`, `actual` only), Sound ("Yes"/"No", `actual` only), Dropped frames (`drops.total`, else `actual.droppedFrames`; 0 reads "None"; omitted when both are nil). Summary: codec, size label, frame rate, colour, joined with " · ".

Seeder: 0 when Captures holds any clip. Else renders `HueSweepPattern` at 1280×720 once on the main actor, then off it writes `OC_000n.MOV` with `AVAssetWriter`: H.264, 30 fps, 90 frames, each frame the picture turned by `CIFilter` hue adjust of `2π·n/90`, tagged Rec. 709 (`AVVideoColorPropertiesKey`), no audio; then `ClipInspector.inspect(url:requestedFrameRate: 30)` and a `ClipSidecar` (requested H.264 "High", tier `.high`, 720p, 30, Rec. 709, `recorder: .system`, outcome "sample") written as `OC_000n.json`. Any failure throws `.seedFailed(function: "seedClipIfAbsent", …)` and removes what it wrote.

- [ ] **Step 1: Failing tests.** `ClipInfoTests`: `aWriterClipListsEveryFact` (ProRes 422 HQ, 3840×2160, 29.97, HLG, 148.2 Mb/s, 60 s, sound, `drops.total` 3: the eight rows in order with values "ProRes 422 HQ", "4K, 3840 × 2160", "29.97 fps", "HLG", "148 Mb/s", "1:00", "Yes", "3"; summary "ProRes 422 HQ · 4K · 29.97 fps · HLG"); `aSystemClipTakesDroppedFramesFromTheFile` (no `drops`, `actual.droppedFrames` 0: "None"); `aClipThatWasNotReadBackShowsWhatWasAsked` (`actual` nil: Codec, Size, Frame rate, Colour only, from `requested`); `aMissingOrUnreadableSidecarSaysSo` (`init(sidecar: nil)`: summary `noClipDetails`, no rows; `load` on an item whose sidecar is `"{"` gives the same); `frameRateAndDataRateText` (the examples above); `noStringHasAnEmDash`. `SampleClipSeederTests`: `seedsOnePlayableClipWithItsSidecar` (returns 1; `LibraryScanner` finds one clip with a sidecar; the sidecar decodes; `actual` is `avc1`, 1280×720, 30 fps, duration 3 ± 0.1 s, `.rec709`); `seedsNothingWhenAClipExists` (second call 0). `LaunchConfigTests.seedClipParsesAndIsScripted`.
- [ ] **Step 2: Run** `scripts/test.sh ClipInfoTests` and `SampleClipSeederTests`. Expected: fail, `ClipInfo` not found.
- [ ] **Step 3: Implement** as above.
- [ ] **Step 4: Run** both suites, `LaunchConfigTests`, then the whole suite. Expected: pass.
- [ ] **Step 5: Commit.** `feat(library): add clip details from the sidecar and a sample clip for the Simulator`

### Task 2: The clip screen

**Files:** Create `OpenCam/UI/Library/ClipScreen.swift`, `OpenCam/UI/InfoLine.swift`. Modify `OpenCam/UI/Editor/PhotoInfoLine.swift` (its body becomes `InfoLine`; `baseHeight` stays as `InfoLine.baseHeight`), `OpenCam/UI/Library/LibraryView.swift` (`tap(_:)` clip branch becomes `path = [item]`; `navigationDestination` switches on `item.kind`; `previewURL`, `.quickLookPreview` and `import QuickLook` go; in `applyLaunch`'s simulator block, `seedsClip` seeds in a `Task` and reloads). No unit test: the screen holds no decision (`ClipInfo` and `LibraryStore.delete` are tested).

**Interfaces. Consumes:** Task 1, `LibraryStore.delete(_:)`, `LibraryCopy`. **Produces:**

```swift
struct InfoLine: View { let title: String; let summary: String; let rows: [PhotoInfoRow]; static let baseHeight: CGFloat = 36 }
// A button that opens a large sheet titled `title` listing `rows` with Done, as PhotoInfoLine does today; with no rows it is
// plain secondary text, not a button.
struct ClipScreen: View { init(item: LibraryItem, library: LibraryStore, onDone: @escaping () -> Void) }
```

Rules. `VideoPlayer(player:)` over `InfoLine(title: LibraryCopy.clipInfoTitle, …)`; the player is made in `.task(id: item.id)` with `AVPlayer(url: item.pictureURL)` and starts playing (Q2), paused in `.onDisappear`. Title `item.stem`, inline. Toolbar, top trailing: `ShareLink(item: item.pictureURL)` labelled "Share" (`square.and.arrow.up`, icon only), then "Delete" (`trash`, destructive, red, icon only). Delete asks `LibraryCopy.deleteClipTitle` with `deleteClipMessage` and one destructive "Delete"; on success pauses and calls `onDone` (the Library pops and reloads, `LibraryView.swift:54-58`); a thrown error shows `LibraryCopy.deleteFailed` and stays. A Log clip plays as recorded.

- [ ] **Step 1: Implement**, run the whole suite (the editor tests cover `PhotoInfoLine`).
- [ ] **Step 2: Screenshots,** `-screen library -seedSamples on -seedClip on`, portrait and landscape: `basics-{v,h}-library` (the clip's cell with its duration badge).
- [ ] **Step 3: Tap checks,** both orientations: the clip cell (the player plays, the line reads the summary); the info line (the "Clip info" sheet lists the rows); Done; Share (the system sheet shows); Cancel; Delete (the dialog); Delete in the dialog (back in the Library, the clip gone). Relaunch with `SHOT_FRESH=1` between orientations so a clip exists. One photo tap still opens the editor.
- [ ] **Step 4: Commit.** `feat(library): play a clip with its details, share and delete`

### Task 3: The pure focus decisions

**Files:** Create in `OpenCam/Capture/`: `FocusPoint.swift`, `PreviewGeometry.swift`, `FocusRequest.swift`, `FocusSupport.swift`, `FocusPlan.swift`, `FocusOutcome.swift`; in `OpenCam/App/`: `FocusTapState.swift`, `FocusMarker.swift`. Tests: `OpenCamTests/PreviewGeometryTests.swift`, `FocusPlanTests.swift`, `FocusTapStateTests.swift`.

**Interfaces. Produces** (all `nonisolated`, `Sendable`, `Equatable`):

```swift
struct FocusPoint { let x: Double; let y: Double; static let centre = FocusPoint(x: 0.5, y: 0.5) }   // both in 0...1, sensor space (F5)
struct PreviewGeometry {
    let viewSize: CGSize; let sensorSize: CGSize; let rotation: Double; let isMirrored: Bool   // rotation in degrees, any value
    func devicePoint(forViewPoint point: CGPoint) -> FocusPoint?   // nil outside the aspect-fit picture or with an empty size
    func viewPoint(for point: FocusPoint) -> CGPoint               // the inverse, for the marker's tests
    static func filling(_ size: CGSize) -> PreviewGeometry         // the Simulator: sensor = view, 0 degrees, not mirrored
}
enum FocusRequest { case point(FocusPoint), lock(FocusPoint), recentre }
struct FocusSupport { var focusPoint = false, exposurePoint = false, autoFocusOnce = false, continuousFocus = false,
                      autoExposeOnce = false, continuousExposure = false }
struct FocusPlan {
    enum Mode { case once, continuous }
    var focusPoint: FocusPoint?; var focusMode: Mode?          // both nil: focus untouched
    var exposurePoint: FocusPoint?; var exposureMode: Mode?    // both nil: exposure untouched
    var watchesSubjectArea: Bool
    var outcome: FocusOutcome
    static func make(_ request: FocusRequest, manual: ManualSettings?, support: FocusSupport) -> FocusPlan
}
enum FocusOutcome { case focusAndExposure, exposureOnly, focusOnly, nothing }
struct FocusMarker { let viewPoint: CGPoint; let serial: Int; let isLocked: Bool }
struct FocusTapState {
    private(set) var marker: FocusMarker?; private(set) var lock: FocusOutcome?   // nil: not locked
    var lockText: String?          // "AE/AF lock", "AE lock", "AF lock"; nil when not locked
    mutating func tapped(at viewPoint: CGPoint, geometry: PreviewGeometry, manual: ManualSettings) -> FocusRequest?
    mutating func held(at viewPoint: CGPoint, geometry: PreviewGeometry, manual: ManualSettings) -> FocusRequest?
    mutating func manualChanged() -> FocusRequest?     // .recentre when locked, then unlocked; else nil
    mutating func cameraChanged()                      // clears marker and lock, asks nothing (the session resets itself)
    mutating func markerFaded(serial: Int)             // clears an unlocked marker with that serial
}
```

Rules.
- Geometry (inverse of `FrameOrientation`): quarter turns from `rotation` rounded to the nearest 90 (non-finite is 0); the shown picture is `sensorSize`, swapped at 90 and 270, aspect-fit and centred in `viewSize` (as `FrameFit`). A view point gives (u, v) in 0...1 of that picture; mirrored first undoes the flip (u = 1 − u); then 0°: (u, v); 90°: (v, 1 − u); 180°: (1 − u, 1 − v); 270°: (1 − v, u).
- Plan. A group set by hand (`manual.focus != nil`, `manual.exposure != .automatic`) is never in the plan; `manual` nil counts as automatic. Focus needs `focusPoint` and its mode; exposure needs `exposurePoint` and its mode. `.point` and `.lock`: mode `.once` when supported, else `.continuous`. `.recentre`: `.centre` and `.continuous`. `watchesSubjectArea` only for `.point` with something in the plan. `outcome` names what the plan holds.
- Tap state. `tapped`: no camera point, or both groups set by hand: nil, nothing shown. Otherwise a new marker (serial + 1, unlocked), the lock ends, `.point`. `held`: the same with a locked marker, `lock` set to the outcome the groups allow, `.lock`. `lockText` from `lock`: both "AE/AF lock", exposure only "AE lock", focus only "AF lock".

- [ ] **Step 1: Failing tests.** `PreviewGeometryTests`: `everyAngleAndMirrorSendsTheCornersToTheSensorsCorners` (the shown picture's top left goes to 0°: (0,0); 90°: (0,1); 180°: (1,1); 270°: (1,0); mirrored at 90°: (0,0); mirrored at 270°: (1,1)); `theCentreIsTheCentreEverywhere`; `aTapInTheBarsIsNotAPoint` (4:3 sensor at 0° in a 16:9 view: a point in the pillar bar is nil; every non-nil point over a 20×20 grid at all eight angle and mirror pairs is inside 0...1); `thePictureIsFittedTurned` (4032×3024 at 90° in 390×844: the shown picture is 390×520, centred); `viewPointRoundTrips` (all eight pairs); `nearlyAQuarterTurnIsOne` (89.6 is 90; NaN is 0); `anEmptyViewHasNoPoints`. `FocusPlanTests`: `aTapSetsBothPointsAndWatchesTheScene`; `aManualFocusKeepsFocusAndMovesOnlyExposure`; `aManualExposureKeepsExposureAndMovesOnlyFocus`; `bothManualDoesNothing` (outcome `.nothing`, no watch); `aCameraThatCannotFocusAtAPointMetersOnly`; `aHoldDoesItOnceAndStopsWatching`; `recentreIsContinuousAtTheCentre`; `onceFallsBackToContinuous`; `withoutAnySupportThereIsNothing`. `FocusTapStateTests`: `aTapShowsTheMarkerAndAsksForThePoint`; `aSecondTapReplacesTheMarkerAndEndsTheLock`; `aHoldLocksAndShowsTheCapsule` ("AE/AF lock"); `aHoldWithFocusSetByHandReadsAELock`; `withBothSetByHandATapShowsNothingAndAsksNothing`; `aTapOutsideThePictureShowsNothing`; `aManualChangeWhileLockedRecentres`; `aManualChangeUnlockedAsksNothing`; `aCameraChangeClearsEverything`; `onlyTheLatestMarkerFades`; `noStringHasAnEmDash`.
- [ ] **Step 2: Run** the three suites. Expected: fail to compile.
- [ ] **Step 3: Implement** as above.
- [ ] **Step 4: Run** the three suites, then the whole suite. Expected: pass.
- [ ] **Step 5: Commit.** `feat(camera): add the pure tap to focus decisions`

### Task 4: Focus in the session

**Files:** Create `OpenCam/Capture/CameraSession+Focus.swift`. Modify `OpenCam/Capture/SessionConfigurator.swift` (one requirement after `applyManual`); `OpenCam/App/SimulatedState.swift` (`StoppedSessionStandIn`: `.nothing`); `OpenCam/Capture/CameraSession.swift:61` (one stored property after `var isRAWClipRecording = false`: `var subjectAreaObserver: (any NSObjectProtocol)?`); `OpenCam/Capture/CameraSession+Manual.swift:65` (one line after `_ = run(request, on: device)`: `resetFocusPoint(on: device)`, so every configure, lens-only change and restart returns the point to the centre with the watch off); `OpenCam/UI/PreviewUIView.swift` (one static function). Tests: `OpenCamTests/FakeSessionConfigurator.swift` (append `applyFocus`: records "focus" in `calls` and the request in `focusRequests`, returns a settable outcome, default `.focusAndExposure`).

**Interfaces. Consumes:** Task 3. **Produces:**

```swift
// SessionConfigurator
/// Runs `FocusPlan.make(request, manual: appliedManual, support:)` on the current camera. Never configures; works while recording.
func applyFocus(_ request: FocusRequest) async -> FocusOutcome
// CameraSession+Focus.swift
func applyFocus(_ request: FocusRequest) -> FocusOutcome
func resetFocusPoint(on device: AVCaptureDevice)    // caller holds the lock: points to the centre where supported, watch off, observer removed
func subjectAreaChanged()                            // runs .recentre when the watch is still on
// PreviewUIView
static func currentGeometry() -> PreviewGeometry?   // the shared view's bounds size, its connection's videoRotationAngle and isVideoMirrored, the device's activeFormat dimensions; nil without a layer, connection or device
static func journalConverterDisagreement(viewPoint: CGPoint, computed: FocusPoint)   // see below
```

Execution. `applyFocus` without a running session or camera returns `.nothing`. It reads `FocusSupport` off the device, makes the plan against the session's own `appliedManual` (so a tap racing a slider apply ends right in either order: the plan skips what is manual when it runs, and an apply only sets manual groups), locks the device (a lock failure is logged as `[CameraSession:applyFocus] Cannot lock the camera for configuration — {lens: …, reason: …}` and returns `.nothing`), sets each point before its mode (F1), `.autoFocus`/`.autoExpose` for `.once`, the continuous modes otherwise, then `isSubjectAreaChangeMonitoringEnabled = plan.watchesSubjectArea`. A watch adds one observer (`queue: nil`, registered by a `nonisolated static` function as `observeNotifications` does, object the device; the block only starts `Task { await owner?.subjectAreaChanged() }`); no watch removes it. Exposure bias, white balance and zoom are untouched.

Converter check. `journalConverterDisagreement` asks the layer's `captureDevicePointOfInterest(for:)` for the same point and, when either coordinate differs by more than 0.02, writes `[Focus:convert] The preview layer disagrees — {view: …, computed: …, layer: …, angle: …, mirrored: …}` through `ErrorJournal.record`. Called by the model in Task 5 on the device only.

- [ ] **Step 1: Implement.** No unit test: every decision is in `FocusPlan` and `PreviewGeometry`; this file only executes it.
- [ ] **Step 2: Run** the whole suite, then the device builds, Debug and Release, 0 warnings.
- [ ] **Step 3: Commit.** `feat(camera): set the focus and exposure point on the camera`

### Task 5: Tap and hold in the viewfinder

**Files:** Create `OpenCam/App/CameraModel+Focus.swift`, `OpenCam/UI/ViewfinderGestureLayer.swift`, `OpenCam/UI/FocusTapRecognizer.swift`, `OpenCam/UI/FocusHoldRecognizer.swift`, `OpenCam/UI/FocusMarkerView.swift`, `OpenCam/UI/FocusLockCapsule.swift`. Modify `OpenCam/App/CameraModel.swift:72` (after `reappliesAllManual`: `var focusTap = FocusTapState()` and `@ObservationIgnored var focusRequests = RenderCoalescer<FocusRequest>()`); `CameraModel+Manual.swift` (the two lines in the touch-point table, and in `resetManual()` after `openControl = nil` at `:129`: `focusTap.cameraChanged()`; a manual shutter that moves the session to the lens's own camera ends a lock through `manualChangedForFocus()`, so the capsule never outlives the configure); the three folded layouts (`.overlay { ViewfinderGestureLayer(model: model) }` on `ViewfinderArea`: `FoldedVerticalView.swift:14`, before `.clipped()`; `FoldedHorizontalView.swift:17`, after the `.frame`; `FoldedVerticalVideoView.swift:13-14`, directly on it); `LaunchConfig.swift` (`var focusLock = false`, `-focusLock on`, Simulator only, scripted). Tests: `OpenCamTests/CameraModelFocusTests.swift`, `LaunchConfigTests.swift` (one test).

**Interfaces. Consumes:** Tasks 3 and 4. **Produces:**

```swift
extension CameraModel {
    var canAim: Bool                    // hasCamera && !isSweeping && !isScanningFormats && !isLibraryPresented && !isViewfinderChanging; recording allowed
    func focusTapped(at viewPoint: CGPoint, in size: CGSize)
    func focusHeld(at viewPoint: CGPoint, in size: CGSize)
    func focusMarkerFaded(serial: Int)
    func manualChangedForFocus()        // sends focusTap.manualChanged()'s request, if any
}
struct ViewfinderGestureLayer: View { let model: CameraModel }   // draws nothing and takes no touch unless model.canAim
```

Rules. The geometry is `PreviewUIView.currentGeometry()` on the device and `.filling(size)` in the Simulator (`isSimulator`). A request goes through `focusRequests` (one in flight, the latest waiting replaces earlier ones, as `sendManual`) to `configurator?.applyFocus`; without a configurator (the Simulator) only the state changes. On the device each tap also calls `journalConverterDisagreement`. `-focusLock on` holds at the centre once the simulated camera is ready.

Views. The layer is `Color.clear.contentShape(.rect)` with the two recognizers, the marker at `focusTap.marker` and the capsule. Tap: `UITapGestureRecognizer`, one touch. Hold: `UILongPressGestureRecognizer`, one touch, 0.5 s, acts at `.began`. A second finger fails both (Task 8's pinch takes it). Marker: a 72 pt square, 1.5 pt stroke in `Theme.accent`, scale 1.2 to 1 over 0.2 s; an unlocked marker stays 2.5 s then fades over 0.5 s and calls `focusMarkerFaded`; a locked one stays. Capsule: `focusTap.lockText` in `Theme.Text.caption`, `.glassEffect(.regular, in: .capsule)` with `LibraryBadge`'s padding, top centre of the picture, `Theme.Space.s` below the top edge (below the readout bar's glass in vertical video, using the same top inset as `DroppedFramesBadge` there); accessibility label the text.

- [ ] **Step 1: Failing tests.** `CameraModelFocusTests` (fake configurator, ready model): `withoutAGestureTheSessionHearsNothingNew` (launch to ready, a lens change, a slider move: no "focus" or "zoom" in `calls`); `aTapReachesTheSessionOnce`; `aBurstOfTapsSendsOnlyTheLatestWhileOneRuns` (fake held: three taps, two requests in all, the last one the third point); `aTapNeverConfigures` (no "configure", `manual` unchanged, `isViewfinderChanging` false); `aTapWorksWhileRecording`; `aSliderMoveWhileLockedSendsRecentre`; `aLensChangeClearsTheLock`; `withBothSetByHandATapSendsNothing`; `inTheSimulatorATapShowsTheMarkerWithoutASession`; `noTapWhileTheViewfinderChanges`. `LaunchConfigTests.focusLockParsesAndIsScripted`.
- [ ] **Step 2: Run** `scripts/test.sh CameraModelFocusTests`. Expected: fail to compile.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the suite, then the whole suite. Expected: pass.
- [ ] **Step 5: Screenshots,** portrait and landscape, photo and video: `basics-{v,h}-{photo,video}-lock` with `-focusLock on` (capsule and locked marker clear of the readouts, the dropped-frames badge and the notice line).
- [ ] **Step 6: Tap checks,** both orientations: tap the picture's upper third (marker there); tap elsewhere (it moves); long press (capsule "AE/AF lock"); tap (capsule gone); open the shutter slider in the picture column (`-sliderPlacement picture -control shutter`) and drag it (the slider moves, no marker); tap the picture beside the column (marker); set focus by hand with the FOCUS slider, long press ("AE lock"); `-state cameraStopped`: tap Try again (it still works, no marker). Wait 4 s after a tap: the marker is gone.
- [ ] **Step 7: Commit.** `feat(camera): tap to focus and expose, hold to lock`

### Task 6: The pure pinch decisions

**Files:** Create `OpenCam/Capture/PinchZoom.swift`. Test: `OpenCamTests/PinchZoomTests.swift`.

**Interfaces. Produces:**

```swift
nonisolated enum PinchZoom {
    static let cap = 10.0                 // Q6
    static let rampRate: Float = 8        // F6: pow(2, 8 t), about 9 ms per 5 percent step
    /// start × magnification in 1...cap; a non-finite or non-positive magnification keeps start.
    static func factor(from start: Double, magnification: Double) -> Double
    /// base × pinch, clamped to base...base × cap and to formatMax (never below base when formatMax < base × cap; formatMax below base gives base).
    static func target(base: Double, pinch: Double, formatMax: Double) -> Double
    /// The strip's text: the lens's own factor (0.5 ultra wide, `zoomFactor` for wide, 1 for the front cameras) × pinch, to one
    /// decimal with ".0" dropped and "x" after; nil when that rounds to the lens's own text.
    static func label(for lens: Lens, pinch: Double) -> String?
    /// True when `next` keeps the pinch: `previous` exists and lens id, mode, video and photo options are equal. A look, sound,
    /// recorder or combined-camera difference keeps it; a lens, mode or format change resets it.
    static func keeps(from previous: SessionConfiguration?, to next: SessionConfiguration) -> Bool
}
```

- [ ] **Step 1: Failing tests.** `withNoPinchTheTargetIsTheConfigurationsZoom` (pinch 1, base 1, 2, 4 and formatMax 129: target equals base exactly); `magnificationScalesFromTheStartFactor` (2 × 1.5 = 3); `clampsBetweenOneAndTheCap` (0.1 gives 1, 100 gives 10, NaN and 0 keep the start); `targetStaysUnderTheFormat` (base 2, pinch 3, max 5: 5; base 4, max 3: 4); `labelReadsTheLiveFactor` (1x at 1.6 "1.6x", 1x at 10 "10x", 0.5x at 2 "1x", 2x at 1.5 "3x", front at 2 "2x", 1x at 1 and 1.04 nil); `keepsAcrossALookChangeButNotLensModeOrFormat` (needsFrames, includesAudio, recorder and combined differences keep; lens, mode, video and photo differences reset; nil previous resets).
- [ ] **Step 2: Run** `scripts/test.sh PinchZoomTests`. Expected: fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the suite, then the whole suite. Expected: pass.
- [ ] **Step 5: Commit.** `feat(camera): add the pure pinch zoom rules`

### Task 7: Pinch in the session

**Files:** Create `OpenCam/Capture/CameraSession+Zoom.swift`. Modify every line in the touch-point table marked Task 7, `CameraSession.swift:61` (`var pinch = 1.0`), `SessionConfigurator.swift` (one requirement), `SimulatedState.swift` (`StoppedSessionStandIn`: returns `pinch`). Tests: `FakeSessionConfigurator.swift` (append `applyZoom`: records "zoom" and the factor in `zoomRequests`, returns `min(pinch, zoomLimit)` with a settable `zoomLimit`, default `PinchZoom.cap`; its `configure` applies the same `keeps` rule to a stored `pinch`).

**Interfaces. Consumes:** Task 6, `SessionConfiguration.zoomFactor`, `lastWorkingConfiguration`. **Produces:**

```swift
// SessionConfigurator
/// Sets the lens-relative pinch on the current camera with a ramp and keeps it for every later re-apply. Returns the pinch the
/// camera can hold (its format may stop short of the cap). Never configures; works while recording.
func applyZoom(pinch: Double) async -> Double
// CameraSession+Zoom.swift
func applyZoom(pinch: Double) -> Double
func targetZoom(for configuration: SessionConfiguration, on device: AVCaptureDevice) -> CGFloat   // PinchZoom.target(base: configuration.zoomFactor, pinch: pinch, formatMax: activeFormat.videoMaxZoomFactor)
func restorePinch(_ configuration: SessionConfiguration, on device: AVCaptureDevice)               // own camera only, pinch ≠ 1: sets targetZoom inside the available range; the combined camera is confirmLens's
```

Rules. `applyZoom` clamps and stores `pinch` first, so a configure or restart later re-applies it even when nothing runs now. With a running session and a camera: lock, and when the target lies in `minAvailableVideoZoomFactor...maxAvailableVideoZoomFactor` ramp to it at `rampRate`; otherwise leave the zoom (the lens lock's range is moving; `settleZoom` and `restoreLens` set it). The target is never clamped to the available range before `settleZoom`'s wait, which needs the real target to wait for. It runs in its own actor turn, so it can never land between `lockLens` and `settleZoom` (`changeLens` and `confirmLens` run both in one turn). The returned pinch is `target / base`. The format choice keeps the base zoom (`CameraSession.swift:536-549`), so a pinch never changes the format.

- [ ] **Step 1: Implement.** No unit test: the numbers come from `PinchZoom`.
- [ ] **Step 2: Run** the whole suite, then the device builds, 0 warnings.
- [ ] **Step 3: Commit.** `feat(camera): keep a pinch zoom across every zoom the session sets`

### Task 8: Pinch in the viewfinder and the strip

**Files:** Create `OpenCam/App/CameraModel+Zoom.swift`, `OpenCam/UI/ZoomPinchRecognizer.swift`. Modify `CameraModel.swift:72` (`var pinch = 1.0`, `@ObservationIgnored var zoomApplies = RenderCoalescer<Double>()`), `:741` (touch-point table), `:629` (the Simulator's twin, one line directly after it: `if !PinchZoom.keeps(from: simulatedConfiguration, to: configuration) { pinch = 1 }`), `ViewfinderGestureLayer.swift` (the pinch recognizer), `OpenCam/UI/StripControl.swift:32-36` (a `model.zoomLabel` shows as `Text` in place of the symbol or short text; the accessibility label gains ", zoom <label>"), `LaunchConfig.swift` (`var pinch: Double?`, `-zoom <factor>` for a finite factor in 1...10, Simulator only, scripted). Tests: `OpenCamTests/CameraModelZoomTests.swift`, `LaunchConfigTests.swift` (one test).

**Interfaces. Consumes:** Tasks 5 to 7. **Produces:**

```swift
extension CameraModel {
    var zoomLabel: String?                       // PinchZoom.label(for: currentLens, pinch:); nil without a camera
    func setPinch(magnification: Double, from start: Double)   // guarded by canAim; sends through zoomApplies to configurator?.applyZoom; adopts the returned pinch when no newer one waits
}
```

Rules. The recognizer is a `UIPinchGestureRecognizer`: at `.began` the layer keeps `model.pinch` as the start, each `.changed` calls `setPinch(magnification: scale, from: start)`. It works while recording, never touches focus, and does not cancel a lock. In the Simulator the pinch only changes the model and the label.

- [ ] **Step 1: Failing tests.** `CameraModelZoomTests`: `aPinchSendsTheFactorWithoutConfiguring` (no "configure", no "manual", blur flag false); `aBurstSendsOnlyTheLatest`; `aLensTapResetsThePinchToOne` (and the fake's stored pinch is 1 after the configure); `aModeSwitchAndAFormatChangeResetIt`; `aLookChangeKeepsIt`; `aPinchWorksWhileRecording`; `theSessionsLimitIsAdopted` (`zoomLimit` 5, pinch to 8: `pinch` 5, label "5x"); `theStripLabelFollowsThePinch` (1x: nil, then "1.6x"); `noPinchWithoutACamera`. `LaunchConfigTests.zoomParsesInsideItsRangeOnly` (`1.6` taken, `0.5`, `11`, `abc` ignored and not scripted).
- [ ] **Step 2: Run** `scripts/test.sh CameraModelZoomTests`. Expected: fail to compile.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the suite, then the whole suite. Expected: pass.
- [ ] **Step 5: Screenshots,** `-zoom 1.6`, portrait and landscape, photo and video: `basics-{v,h}-{photo,video}-zoom` (the strip's lens item reads "1.6x" in the strip's own style, nothing clipped).
- [ ] **Step 6: Tap checks,** both orientations, launched with `-zoom 1.6`: open the lens menu and pick 0.5x (the label returns to "0.5x"); switch mode (label back to the lens); relaunch with `-zoom 1.6`, open Record settings and pick another look (still "1.6x"); tap the picture (marker, still "1.6x"). The pinch gesture itself cannot be scripted: it is for the owner in the Simulator (option-drag) and on the phone.
- [ ] **Step 7: Commit.** `feat(camera): pinch to zoom within the current lens`

### Task 9: Device checklist

**Files:** Modify `docs/device-checklist.md`: new section "## 12. Camera basics" directly before "## 9. Things to decide after holding it".

- [ ] **Step 1: Write the section,** these items:
  - Clip: tap a clip; it plays at once with sound from the speaker, not the earpiece (note which, with and without headphones). The info line and "Clip info" match the `.json`. Share to Files and AirDrop. Delete removes the MOV and the `.json`. A ProRes 4K clip and a Log clip play (Log looks flat). Return to the camera: it runs on the same lens.
  - Tap: on the back 1x, 0.5x and 2x and both front cameras, in all four orientations, tap a near object at the screen's edge: that object sharpens and exposes. Then copy `opencam-errors.log`: no `[Focus:convert]` line. If there is one, note the angle and mirror it names.
  - Front cameras: exposure only, the marker still shows.
  - Manual focus set, tap: focus does not move, exposure does. Manual shutter set, tap: only focus moves. Both set: nothing shows.
  - Move the camera to a new scene after a tap: focus and exposure return to the centre within a second or two. After a hold: they stay, the capsule stays, until the next tap.
  - During a recording: a tap and a hold work, no blur, no dropped frames, `drops.total` 0. Note whether the focus change is smooth in the clip.
  - A lens tap on the combined camera after a hold: the capsule goes, the new lens focuses at the centre.
  - With a look on: the marker lands where the finger was.
  - Pinch: smooth from 1x up to the cap on 0.5x, 1x and 2x, on the combined camera (video up to 60 fps) and on a lens's own camera (photo, 120 fps). Note where each stops short of 10x.
  - Pinch on 1x of the combined camera: the picture stays the wide lens (never the ultra wide cropped) up to the cap.
  - Pinch during a recording: smooth in the clip, no blur, no dropped frames, sound in sync.
  - Pinch, then a phone call, the Library and back, a look on and off, and backgrounding: the zoom and the "1.6x" label are kept. A lens tap, a mode switch and a format change return it to the lens.
  - Pinch, then a manual shutter (moves to the lens's own camera): the zoom stays the same framing.
  - Pinch with two fingers starting on the picture: no marker and no lock appear.
- [ ] **Step 2: Device builds,** Debug and Release, 0 warnings; whole suite once more, with the totals from `xcrun xcresulttool get test-results summary --path <newest .xcresult under .build/Logs/Test>`.
- [ ] **Step 3: Commit.** `docs: add the camera basics device checks`

## Not in this plan

- Viewing a Log clip through the inverse table.
- iOS 27's continuous autofocus tracking (F7) and the iOS 26 rectangles of interest.
- Pinching across lenses, and the Camera Control's zoom.
- Dragging the marker to change exposure bias.
- Saving the pinch or the lock across launches.
- Clip trimming or frame export.

## To confirm on the phone

Everything in section 12. The headers do not state: whether the preview layer's converter accounts for rotation and mirroring (the journal line decides whether `PreviewGeometry` or the layer is right); whether the subject-area notice fires on the combined camera's locked lens; whether a 0.5 s ramp at rate 8 looks smooth in a recording; where each format's `videoMaxZoomFactor` stops the cap; which audio route a clip plays to after the camera released the audio session for the Library.

## Open questions (decided here; the owner may overrule)

- Q1 Replace Quick Look with `ClipScreen` (A, planned), or keep Quick Look and add details elsewhere (B; Quick Look cannot carry delete or the details).
- Q2 The clip plays at once (A, planned, as Photos does) or opens paused (B).
- Q3 Share is `ShareLink` on the file (A, planned); `ShareSheet` (B) exists for a temporary export and would add sheet state for nothing.
- Q4 `PreviewGeometry` decides the point and the layer's converter is only journalled (A, planned, testable without hardware); trust the layer's converter alone (B, fewer lines, behaviour the header does not promise).
- Q5 A tap focuses and exposes once, then holds until the scene changes (A, planned, `.autoFocus`/`.autoExpose` with the subject-area watch); continuous at the point (B, keeps hunting at that point).
- Q6 Cap at 10 times the lens (A, planned, as asked and well inside 4K formats' `videoMaxZoomFactor` of about 129); cap at the format's `videoZoomFactorUpscaleThreshold` (B, no upscaled frames, likely about 2x on a 48 MP sensor).
- Q7 A look change, a sound change, the Library, a restart and the move to a lens's own camera keep the pinch (A, planned); every configure resets it, as manual controls do (B, simpler, loses zoom on a look toggle).
