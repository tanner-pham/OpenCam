# OpenCam Manual Controls Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. All paths are relative to the worktree root, `/Users/tannerpham/CS Projects/DuoCam/.claude/worktrees/feat+camera-core`.

**Goal:** Tapping the SHUTTER, ISO, EV, WB, TINT or FOCUS readout opens a vertical slider for that setting, in the side strip on the folded Duo, that sets the camera by hand, with Auto to hand it back.

**Architecture:** One value, `ManualSettings`, says what the user has set by hand. The model owns it, sends it whole to the session through a one-in-flight coalescer, and returns it to automatic whenever the camera changes. The session turns each snapshot into a pure, tested `ManualApplyPlan` (what changed, clamped to the device's limits) before it touches the device, and never reconfigures. Readouts become small buttons that each read their own control; the strip's item list is a pure function of which control is open, read by one small modifier, so opening a slider re-runs that modifier and a drag re-runs only the slider and the readouts.

**Tech Stack:** Swift 6 (MainActor default isolation), SwiftUI with system glass, AVFoundation, Swift Testing. No new dependencies.

**Spec:** The owner, verbatim: "Clicking an adjustable option, such as shutter, iso, EV, WB, and focus should open a slider on the "control strip area" that the user can slide up and down to adjust the setting. For the Duo, these should be on the side control strip to clean up the viewfinder." The controller's decisions, as planned (numbers point at "Read first"):

- Controls: shutter, ISO, EV, white balance temperature, tint, focus. Tapping a readout opens its slider, tapping another switches, tapping the open one or the close item closes. The open readout is marked; a value set by hand is marked differently. **Only controls with a readout in the current layout can be reached (1).**
- Folded display: slider, Auto (not for EV) and close replace Mode, Lens and Library in the strip. **Open display, both orientations: the same three views in a glass column at the edge of the picture (2).**
- Exposure: the first slider move on shutter or ISO sets custom exposure with the other value held where the camera has it; Auto returns both. Opening a slider changes nothing. **While exposure is manual, EV reads `--`, is dimmed and cannot be opened (3).**
- White balance: temperature and tint over the device's gains, clamped to 1...`maxWhiteBalanceGain`; the value not being moved is taken from the live readout at the first move. Focus: lens position 0...1, locked.
- Scales: shutter in the conventional third-stop series inside the format's limits, in video ending at the frame time and including the frame rate's own two values (Q3); ISO in conventional third stops plus the format's two ends; EV in thirds over the format's system-recommended range, else the device's (Q4); temperature 2500 to 10000 K by 100; tint -50 to +50 by 1; focus by 0.01. Up is more (Q6). **A haptic at each step for shutter, ISO, EV and temperature; at each 10 for tint and each quarter for focus (9).**
- **Every session configure returns every control to automatic and closes the slider: lens and mode, and also a format, sound or look change (6).** Nothing manual is saved. Manual values are not in `SessionConfiguration`, never reconfigure, never raise `isViewfinderChanging`, and work while recording.
- The Simulator gets simulated ranges and values **(10)**.

## Read first: what the code and SDK change

1. **Not every control has a readout to tap.** `OpenCam/UI/TopReadoutBar.swift:13-18` shows FPS, SHUTTER, TIMECODE, ISO, WB, TINT; `OpenCam/UI/PhotoReadoutRow.swift:10-14` shows SHUTTER, ISO, EV, WB, FOCUS; `OpenCam/UI/FoldedHorizontalView.swift:14` uses the top bar in landscape for both modes (`docs/screenshots/qa/qa-outer-photo-h.png`). So: portrait video and all landscape reach shutter, ISO, WB, tint; portrait photo reaches shutter, ISO, EV, WB, focus. EV and focus cannot be reached in video or in landscape; tint cannot in portrait photo. The compact video bar has about 47 pt per readout and no room for two more. This plan wires every adjustable readout that exists and supports all six controls underneath. See Q1.
2. **The open display has a strip in landscape.** `docs/screenshots/qa/qa-inner-l-camera-photo.png` and `qa-inner-l2-camera-video.png` show the pill in a vertical bar on the trailing edge; the comment replaced in `e2e332f` said "the system's bar on the side (the folded phone, and the open phone in landscape)". Only open portrait has the floating horizontal bar (`qa-inner-p-camera-video.png`), where a 200 pt tall item is untested. So placement is a function of posture and `toolbarVerticalEdge`, not "open means no strip". The strip swap is proven only on the folded display, so the open display uses the in-picture column in both orientations until someone can test it. See Q2.
3. **EV does nothing in full manual.** `AVCaptureDevice.h:1678`: with custom exposure and no Auto parameter "bias is disabled and will only affect metering". The device keeps its bias and it applies again on Auto. The Camera Control's EV control is disabled meanwhile through `AVCaptureControl.isEnabled` (`AVCaptureControl.h:40`), which needs no session configuration.
4. **A photo can ignore manual exposure.** `AVCaptureDevice.h:1466`: with balanced prioritization the device's ISO and duration "may be overridden"; honouring them needs `.speed`. Today HEIF uses balanced (`OpenCam/Capture/PhotoSettingsPlan.swift:16`, `PhotoCapturer.swift:42`). While exposure is manual every photo takes `.speed`; that photo loses stabilisation and fusion.
5. **Shutter and frame rate are tied.** `AVCaptureDevice.h:430`: a custom duration longer than `activeVideoMaxFrameDuration` lengthens it, and a shorter one later does not bring it back. Video: the shutter is clamped to the frame time (`CameraSession.swift:440-441` pins it), or the clip's frame rate would drop. Photo: the session returns `activeVideoMaxFrameDuration` to its default (`.invalid`, as `CameraSession.swift:469-470` does) before each manual exposure and on Auto, so the preview's rate recovers.
6. **"Lens or mode" is every configure.** `applyVideo` sets `activeFormat` again on each configure (`CameraSession.swift:437`) and the header does not say custom exposure survives that. One rule on both sides (the session sets the device automatic at the end of every `apply`, the model resets when it queues a configure) cannot diverge. A look change in Record settings therefore also resets.
7. **`whiteBalanceRestore`** (`CameraSession.swift:46`, `:615-645`) locks white balance for a ProRes RAW clip and restores the earlier mode after. A manual lock set before the clip is already left in place (`:617`). Two cases break: set by hand during the clip (the restore would undo it) and Auto during the clip (must stay locked until the clip ends). Task 3's plan decides both.
8. **Camera Control** (`installSystemControls`, `CameraSession.swift:672-704`; `CameraControlPlan.swift`): its EV slider and the app's write the same device property. The app's readout and thumb follow the device (the poll), and the session writes bias only when the app's EV slider moved (`ManualSettings.bias == nil` means leave it). `AVCaptureSession.h:743` asks apps to hide their own sliders when the controls go full screen; the comment at `CameraControlsDelegate.swift:4-5` ("draws no ... sliders of its own") stops being true, so the open slider closes then (Task 6). Zoom is untouched.
9. **A haptic per step cannot hold for tint and focus:** 101 steps over about 170 pt of travel is a continuous buzz. They get detents.
10. **The Simulator's readouts are pinned to `--`** by `CameraModel.shownReadouts` (`CameraModel.swift:298-299`) and `ControlsAndReadoutsTests.swift:29-35`. Task 5 changes both on purpose; every later Simulator screenshot shows simulated values where the QA set shows `--`.
11. **The strip swap depends on neither claim about toolbar bodies.** `StripToolbar.swift:5-6` says the toolbar's body is not re-run on model changes; the spike saw a conditional read there update. Here a small `ViewModifier` reads `model.openControl` and passes the item list in as a plain value, the way `isLandscape` reaches the toolbar today.

## Global Constraints

- Branch `feat/manual-controls` from `perf/launch-fast-path`. The camera core plan's constraints apply: strict Swift 6 concurrency, no force unwraps or `try!`, one type per file, errors as `[Module:Function] Description — {context}`, no `@unchecked Sendable`, `nonisolated(unsafe)` or `@preconcurrency import`, conventional commits, no attribution lines.
- API facts only from the SDK headers (iPhoneOS27.2) or `docs/research/capture-apis.md` sections 2 and 7 (git-ignored: cite, never commit).
- No manual change calls `configure`, `selectionChanged` or `beginConfiguration`, touches `SessionConfiguration`, `SavedSelections` or `SavedStart`, or raises `isViewfinderChanging`.
- No device setter runs with a number that `ManualApplyPlan` did not clamp in the same actor turn, and every mode is set behind its `is…Supported` check.
- At most one `applyManual` in flight; a newer snapshot replaces the waiting one; the last one is always sent.
- A video shutter never exceeds the frame time. Controls work while recording.
- Strip items stay `ToolbarItem(placement: .bottomBar)` with `.axisBehavior(.verticalPreferred)`. `onCameraCaptureEvent` stays on the NavigationStack's content. Nothing is drawn into the strip's empty column (spike Q2: no touches).
- Only `ControlReadout`, `ControlSlider`, `ControlAutoButton`, `StripToolbarModifier` and `PictureSliderColumn` read manual state. The same slider, Auto and close views serve the strip and the picture. `ReadoutView` gains variants; nothing is forked per layout.
- Copy: the strings in the tasks are final. Plain, sentence case, no em dashes.
- Every interactive control is tap-tested on the folded Simulator "OpenCam Dev", portrait and landscape: one action, wait 2 seconds, `xcrun simctl io "$(scripts/sim-udid.sh)" screenshot --display=1 <file>`, look at it. Drags use the spike's path (6 points, 30 pt apart, 100 ms between points).
- The open display cannot be run. Nothing about it is claimed as verified; it goes on the device checklist.
- Screenshots: `docs/screenshots/manual-controls/`, names `manual-…`.

## Review Focus

1. **The readout says one thing and the camera does another after a camera change:** a slider moved while a lens change is queued, or an apply landing after the configure. Pinned by `ManualLifecycleTests.aSliderMovedWhileTheCameraChangesIsNotSent` and `theConfigureWaitsForTheApplyInFlight` (Task 6).
2. **A value outside the device's limits reaches AVFoundation and raises an exception Swift cannot catch:** stale ranges, a shutter past the frame time, gains outside 1...max, NaN. Pinned by `ManualSettingsTests.clampingKeepsEveryValueInsideItsRange`, `aVideoShutterNeverExceedsTheFrameTime` (Task 2) and `ManualSessionTests.gainsStayBetweenOneAndTheMaximum` (Task 3).
3. **Drags outrun the session:** applies pile up and the camera lags the finger, or the last value is dropped. Pinned by `ManualControlTests.aBurstWhileOneApplyRunsSendsOnlyTheLatest` (Task 5).
4. **The strip is left showing a slider with no Mode, Lens or Library** when the control stops being adjustable (camera stopped, interruption, sweep, Library). Pinned by `ManualLifecycleTests.theSliderClosesWheneverItsControlCannotBeAdjusted` (Task 6) and `StripItemsTests.theStripShowsTheThreeItemsWhenNoControlIsOpen` (Task 8).
5. **Another capture path undoes a manual value without saying so:** a RAW clip's white-balance restore, a photo's balanced prioritization. Pinned by `ManualSessionTests.whiteBalanceAroundARAWClip` (Task 3) and `PhotoCaptureTests.aManualExposurePhotoPrioritizesSpeed` (Task 4).

---

### Task 1: Scales and spoken values

**Files:** Create `OpenCam/Capture/ManualControl.swift`, `ManualGroup.swift`, `ManualRanges.swift`, `ManualScale.swift`. Test: `OpenCamTests/ManualScaleTests.swift`.

**Interfaces — Produces:**

```swift
nonisolated enum ManualControl: String, Sendable, CaseIterable {
    case shutter, iso, bias = "ev", temperature = "wb", tint, focus   // raw values are the -control launch values
    var caption: String      // "SHUTTER" "ISO" "EV" "WB" "TINT" "FOCUS", as the readouts read today
    var name: String         // "Shutter" "ISO" "Exposure bias" "White balance" "Tint" "Focus"
    var group: ManualGroup
    var hasAutomatic: Bool   // false for .bias
    func text(_ value: Double?) -> String     // ReadoutFormatter's text; nil reads "--"
    func spoken(_ value: Double?) -> String   // "1/60 second" "2.5 seconds" "ISO 400" "+0.3 EV" "5600 kelvin" "Tint +4" "Focus 0.85"; nil: "Not available"
}
nonisolated enum ManualGroup: Sendable, CaseIterable { case exposure, bias, whiteBalance, focus }

/// What the current camera and its active format allow. Nil or false: this camera cannot set that control.
nonisolated struct ManualRanges: Sendable, Equatable {
    var shutterSeconds: ClosedRange<Double>?   // in video the upper end is the frame time
    var iso: ClosedRange<Float>?
    var bias: ClosedRange<Float>?
    var hasWhiteBalance = false
    var hasFocus = false
    var frameSeconds: Double?                  // video only
}
nonisolated struct ManualScale: Sendable, Equatable {
    let values: [Double]      // ascending, never empty; step 0 is the bottom of the slider
    let detentStride: Int     // a haptic each time the thumb crosses a multiple of this
    let adjustStride: Int     // steps per VoiceOver increment
    let isLogarithmic: Bool   // shutter and ISO: nearest by stops
    static func make(for control: ManualControl, ranges: ManualRanges) -> ManualScale?
    func step(nearest value: Double) -> Int
    func step(_ step: Int, movedBy steps: Int) -> Int     // clamped to the scale
    func crossesDetent(from: Int, to: Int) -> Bool
}
```

Rules. Shutter: 1/n s for n in 8000, 6400, 5000, 4000, 3200, 2500, 2000, 1600, 1250, 1000, 800, 640, 500, 400, 320, 250, 200, 160, 125, 100, 80, 60, 50, 40, 30, 25, 20, 15, 13, 10, 8, 6, 5, 4, 3, 2.5, 2, 1.6, 1.3, 1, kept when inside the range; with `frameSeconds`, add it and half of it and drop any table value within 2 percent of either. ISO: 25, 32, 40, 50, 64, 80, then 100, 125, 160, 200, 250, 320, 400, 500, 640, 800 times each power of ten, inside the range, plus the range's two ends. EV: k/3. Strides (detent, adjust): shutter, ISO, EV, temperature 1, 1; tint 10, 5; focus 25, 5.

- [ ] **Step 1: Failing tests.** `shutterStopsStayInsideTheFormat` (ascending, unique, all inside 1/8000...1/3); `aVideoShutterEndsAtTheFrameTime` (frame 1/24: last is 1/24, contains 1/48, nothing longer; frame 1/30: one 1/30); `isoRunsInThirdStopsAndIncludesBothEnds` (34...6400: first 34, then 40, last 6400); `evStepsAreThirdsAndIncludeZero`; `temperatureStepsBy100K` (76 values); `aCameraThatCannotSetAControlHasNoScale` (nil range or false flag gives nil); `nearestStepUsesStops` (1/97 s is the 1/100 step); `detents` (stride 1: any change; tint 52 to 57 false, 57 to 61 true, 49 to 51 true); `spokenValues` (each string above; none has an em dash).
- [ ] **Step 2: Run and see fail.** `scripts/test.sh ManualScaleTests`, exit 65.
- [ ] **Step 3: Implement.** Foundation only, all `nonisolated`.
- [ ] **Step 4: Run** the suite, then all of `scripts/test.sh`.
- [ ] **Step 5: Commit.** `feat: add the scales manual controls step through`

### Task 2: The settings value and its rules

**Files:** Create `OpenCam/Capture/ManualSettings.swift`. Modify `OpenCam/Capture/ManualRanges.swift` (`clamped`). Test: `OpenCamTests/ManualSettingsTests.swift`.

**Interfaces — Consumes:** Task 1, `LiveReadouts`. **Produces:**

```swift
/// What the user has set by hand. `.automatic` at launch and after every camera change. Never saved.
nonisolated struct ManualSettings: Sendable, Equatable {
    enum Exposure: Sendable, Equatable { case automatic; case manual(shutterSeconds: Double?, iso: Float?) }   // nil holds the value the camera has now
    enum WhiteBalance: Sendable, Equatable { case automatic; case manual(kelvin: Float, tint: Float) }
    var exposure = Exposure.automatic
    var bias: Float?           // nil: never set here, so the camera's own bias is left alone
    var whiteBalance = WhiteBalance.automatic
    var focus: Float?          // nil: continuous autofocus
    static let automatic = ManualSettings()
    var isAutomatic: Bool      // bias does not count
    func setting(_ control: ManualControl, to value: Double, live: LiveReadouts) -> ManualSettings
    func settingAutomatic(_ control: ManualControl) -> ManualSettings      // shutter or ISO: both; temperature or tint: both; bias: unchanged
    func value(of control: ManualControl, live: LiveReadouts) -> Double?   // what the readout and thumb show
    func isSet(_ control: ManualControl) -> Bool                           // shutter and ISO together; never .bias
    func isAdjustable(_ control: ManualControl) -> Bool                    // false only for .bias while exposure is manual
    func changedGroups(from applied: ManualSettings?) -> Set<ManualGroup>  // nil: every group (bias only when set)
}
extension ManualRanges { func clamped(_ settings: ManualSettings) -> ManualSettings }
```

Rules. Temperature's first move takes tint from `live.tint`, else 0; tint's takes kelvin from `live.kelvin`, else 5600. `value(of: .bias)` is nil while exposure is manual. `clamped`: each number into its range (kelvin 2500...10000, tint -150...150, focus 0...1); a non-finite exposure number becomes nil (hold); a non-finite white balance, focus or bias, or a group this camera lacks, becomes automatic or nil.

- [ ] **Step 1: Failing tests.** `theFirstMoveOfShutterOrISOLocksBothAndHoldsTheOther`; `autoOnEitherReturnsBoth`; `evIsNotAdjustableWhileExposureIsManualAndReadsMissing`; `temperatureTakesTintFromTheLiveReadoutAndTintTakesTemperature` (and both fallbacks); `focusLocksAndAutoReleases`; `readoutValuesAreLiveInAutoAndTheSetValueByHand` (a held shutter shows the live one and `isSet`); `clampingKeepsEveryValueInsideItsRange` (ISO above the maximum, NaN in each field, focus 1.2, a camera without focus); `aVideoShutterNeverExceedsTheFrameTime`; `changedGroupsNamesOnlyWhatDiffers`.
- [ ] **Step 2: Run and see fail.** `scripts/test.sh ManualSettingsTests`.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the suite, then everything.
- [ ] **Step 5: Commit.** `feat: add the manual settings value and its rules`

### Task 3: The session's manual surface, with the fake

**Files:** Create `OpenCam/Capture/ManualControlError.swift`, `ManualApplyPlan.swift`, `CameraSession+Manual.swift`. Modify `OpenCam/Capture/SessionConfigurator.swift`, `OpenCam/Capture/CameraSession.swift` (stored `appliedManual: ManualSettings?` and `isRAWClipRecording`; `session`, `videoInput`, `lastWorkingConfiguration` and `whiteBalanceRestore` lose `private` so the extension file can reach them), `OpenCamTests/FakeSessionConfigurator.swift`. Test: `OpenCamTests/ManualSessionTests.swift`.

**Interfaces — Produces:**

```swift
// SessionConfigurator gains:
/// What the current camera reports now; empty while the session is stopped or holds no camera.
func currentReadouts() async -> LiveReadouts
/// What the current camera and its active format allow by hand; nil while the session is stopped or holds no camera.
func manualRanges() async -> ManualRanges?
/// Sets the camera to `settings`, changing only the groups that differ from the last settings applied to this camera;
/// `reapplyingAll` sets every group. Never reconfigures the session; works while recording. Every value is clamped to
/// the device's limits first, and the settings actually set are returned. A configure returns the camera to automatic.
func applyManual(_ settings: ManualSettings, reapplyingAll: Bool) async throws(ManualControlError) -> ManualSettings

nonisolated enum ManualControlError: Error, CustomStringConvertible, Equatable {
    case noCamera                                  // "[CameraSession:applyManual] No running camera — {running: false}"
    case lockFailed(reason: String)                // "[CameraSession:applyManual] Cannot lock the camera for configuration — {reason: …}"
    case notSupported(control: String, lens: String)   // "[CameraSession:applyManual] Control not supported by this camera — {control: focus, lens: front}"
}

/// What one apply sets, decided from plain numbers before any device call, because a value outside the device's limits
/// raises an exception Swift cannot catch.
nonisolated struct ManualApplyPlan: Sendable, Equatable {
    enum Exposure: Sendable, Equatable { case continuous; case custom(seconds: Double?, iso: Float?) }
    enum WhiteBalance: Sendable, Equatable { case continuous; case continuousAfterClip; case locked(kelvin: Float, tint: Float) }
    enum Focus: Sendable, Equatable { case continuous; case locked(Float) }
    var exposure: Exposure?            // nil: leave as it is
    var bias: Float?
    var whiteBalance: WhiteBalance?
    var focus: Focus?
    var applied: ManualSettings        // the clamped settings the camera has once this plan has run
    static func make(_ settings: ManualSettings, applied: ManualSettings?, limits: ManualRanges, lens: String,
                     isRAWClipRecording: Bool) throws(ManualControlError) -> ManualApplyPlan
    static func clampedGain(_ gain: Float, max: Float) -> Float     // non-finite gives 1
}
// FakeSessionConfigurator gains: setReadouts(_:), setRanges(_:), setManualError(_:), holdManual(), resumeManual(),
// manualApplies: [(settings: ManualSettings, reapplyingAll: Bool)], and "manual" in calls. It returns ranges.clamped(settings).
```

Device calls and the guard in front of each (`CameraSession+Manual.swift`, one `lockForConfiguration` per apply):

| Call | Guard |
|---|---|
| `setExposureModeCustom(duration:iso:completionHandler:)` (raises, `AVCaptureDevice.h:1616-1617`) | `isExposureModeSupported(.custom)`. Duration nil: `AVCaptureDevice.currentExposureDuration` (`:1601`); else a `CMTime` clamped in `CMTime` between `activeFormat.minExposureDuration` and the upper bound (video: the lesser of `maxExposureDuration` and `activeVideoMaxFrameDuration`; photo: `maxExposureDuration`). ISO nil: `currentISO`; else `minISO...maxISO`. |
| `exposureMode = .continuousAutoExposure` | `isExposureModeSupported` |
| `setExposureTargetBias(_:completionHandler:)` (raises, `:1719`) | `minExposureTargetBias...maxExposureTargetBias`; only while the plan's exposure is automatic |
| `deviceWhiteBalanceGains(for:)` then `setWhiteBalanceModeLocked(with:completionHandler:)` (raises, `:1946`, `:2006`) | `isLockingWhiteBalanceWithCustomDeviceGainsSupported` (`:1866`), `isWhiteBalanceModeSupported(.locked)`; each gain through `clampedGain` |
| `temperatureAndTintValues(for:)` (raises, `:1991`) | called only on clamped gains, to report what was set when a gain was clamped |
| `whiteBalanceMode = .continuousAutoWhiteBalance` | `isWhiteBalanceModeSupported` |
| `setFocusModeLocked(lensPosition:completionHandler:)` (raises, `:1373`) | `isFocusModeSupported(.locked)`, `isLockingFocusWithCustomLensPositionSupported` (`:1218`); 0...1 |
| `focusMode = .continuousAutoFocus` | `isFocusModeSupported` |
| `activeVideoMaxFrameDuration = .invalid` | photo mode only, `!isAutoVideoFrameRateEnabled` |

- [ ] **Step 1: Failing tests.** `thePlanSetsOnlyWhatChanged` (focus moved: exposure, bias and white balance nil); `thePlanSetsEverythingWhenNothingIsKnown`; `biasIsSetOnlyWhileExposureIsAutomatic`; `aControlTheCameraLacksThrowsBeforeAnythingIsSet` (`.notSupported(control: "focus", …)`); `gainsStayBetweenOneAndTheMaximum` (0.4 gives 1, 9 with max 4 gives 4, NaN gives 1); `whiteBalanceAroundARAWClip` (set by hand during the clip: `.locked`; Auto during the clip: `.continuousAfterClip`; Auto otherwise: `.continuous`); `errorsReadInTheHouseFormat`; `theFakeRecordsEachApplyAndClampsLikeTheSession`.
- [ ] **Step 2: Run and see fail.** `scripts/test.sh ManualSessionTests`.
- [ ] **Step 3: Implement.** `manualRanges()` reads the table's limits off the device, with bias from `activeFormat.systemRecommendedExposureBiasRange` when present. `applyManual` builds the limits and the plan, runs it, stores `appliedManual = plan.applied`. No completion handler is awaited: pacing is the model's coalescer. `.locked` clears `whiteBalanceRestore`; `.continuousAfterClip` leaves the device locked and sets `whiteBalanceRestore` to continuous. A clamped value is logged, not thrown.
- [ ] **Step 4: Run** the suite, everything, and the device SDK build with 0 warnings.
- [ ] **Step 5: Commit.** `feat: let the session set exposure, white balance and focus by hand`

### Task 4: The session paths manual settings meet

**Files:** Modify `OpenCam/Capture/CameraSession.swift` (`apply`, `restartAfterMediaServicesReset`, `startRecording`, `restoreWhiteBalance`, `requestPhoto`), `PhotoCapturer.swift`, `PhotoSettingsPlan.swift`, `CameraControlPlan.swift`, `CameraSession+Manual.swift`. Tests: `OpenCamTests/PhotoCaptureTests.swift`, `ControlsAndReadoutsTests.swift`.

**Interfaces — Produces:**

```swift
// PhotoSettingsPlan.make gains isExposureManual: Bool; prioritizesSpeed is true for RAW or manual exposure.
extension CameraControlPlan { static func enablesExposureBias(for exposure: ManualSettings.Exposure) -> Bool }   // false while manual
```

- [ ] **Step 1: Failing tests.** `aManualExposurePhotoPrioritizesSpeed` (HEIF with `isExposureManual: true` prioritizes speed, false does not); `controlPlan` gains the two `enablesExposureBias` cases.
- [ ] **Step 2: Run and see fail.**
- [ ] **Step 3: Implement.** (a) At the end of every successful `apply(_:)`, and after the restart in `restartAfterMediaServicesReset`, the session sets the device automatic (continuous exposure, bias 0, continuous white balance, continuous autofocus, each behind its support check) and `appliedManual = nil`; a lock failure is logged as `[CameraSession:resetManual] Cannot lock the camera for configuration — {lens: …, reason: …}` and does not fail the configure. (b) `startRecording` sets `isRAWClipRecording` for a RAW option; `restoreWhiteBalance` clears it even when nothing is to restore. (c) `requestPhoto` passes `device.exposureMode == .custom`. (d) After the exposure group is applied, each `AVCaptureSystemExposureBiasSlider` in `session.controls` gets `isEnabled = CameraControlPlan.enablesExposureBias(for:)`.
- [ ] **Step 4: Run** everything and the device SDK build.
- [ ] **Step 5: Commit.** `feat: keep manual settings through RAW clips, photos and the Camera Control`

### Task 5: The model's state, sending and readouts

**Files:** Create `OpenCam/App/CameraModel+Manual.swift`, `ControlReadoutState.swift`, `OpenSlider.swift`, `SimulatedCamera.swift`. Modify `OpenCam/App/CameraModel.swift` (stored properties; `shownReadouts` becomes `hasCamera ? readouts : LiveReadouts()`; the six `…Text` accessors at `:300-305` go; `pollReadouts` at `:825-835` becomes a loop over `refreshReadouts(from:)`; `controlStepped()` beside `recordingBegan`, because `feedback` is `private(set)`; Simulator seeding in `init`), `CaptureFeedback.swift`, `NoticeSource.swift` (`.control`), `LaunchConfig.swift`. Tests: `OpenCamTests/ManualControlTests.swift`, `ControlsAndReadoutsTests.swift`, `LaunchConfigTests.swift`.

**Interfaces — Consumes:** Tasks 1 to 3, `RenderCoalescer` as `EditorModel.swift:176-192` uses it. **Produces:**

```swift
// CameraModel stored: var manual = ManualSettings.automatic; var openControl: ManualControl?; var manualRanges: ManualRanges?
//   @ObservationIgnored: manualApplies = RenderCoalescer<ManualSettings>(), manualApplyTask, appliedManual, manualGeneration, reappliesAllManual
extension CameraModel {
    var canAdjustControls: Bool        // hasCamera, no sweep, scan or Library, and requestedConfiguration == lastWorking?.configuration
    func scale(for control: ManualControl) -> ManualScale?
    func readout(for control: ManualControl) -> ControlReadoutState
    var openSlider: OpenSlider?
    func toggleControl(_ control: ManualControl)          // opens, switches, or closes the open one
    func closeControl()
    func setControl(_ control: ManualControl, step: Int)
    func setAutomatic(_ control: ManualControl)
    func refreshReadouts(from configurator: any SessionConfigurator) async   // one poll: readouts, then ranges
}
nonisolated struct ControlReadoutState: Sendable, Equatable { var text: String; var spoken: String; var isSet: Bool; var isOpen: Bool; var isAvailable: Bool }
nonisolated struct OpenSlider: Sendable, Equatable { var control: ManualControl; var stepCount: Int; var step: Int?; var adjustStride: Int; var text: String; var spoken: String; var isAutomatic: Bool }
nonisolated enum SimulatedCamera { static func readouts(mode: CaptureMode, frameRate: Int) -> LiveReadouts; static func ranges(mode: CaptureMode, frameRate: Int) -> ManualRanges }
// CaptureFeedback.controlSteps: Int; LaunchConfig.openControl: ManualControl?  (-control shutter|iso|ev|wb|tint|focus, Simulator only, scripted)
```

Decisions. State is one value (`manual`) plus two properties observed apart because their readers differ: `openControl` (the strip's modifier, which must not re-run per drag step) and `manualRanges` (scales). The session reads the ranges from the device on every poll and the model keeps the last copy; nothing caches them across cameras. `setControl` changes `manual` at once, counts a haptic when the step crosses a detent, and sends the whole snapshot: `manualApplies.request(manual)` starts a task only when none runs, and each returning apply sends the latest waiting snapshot. A result from before a reset (`manualGeneration`) is ignored. On success `appliedManual` is what the session returned, adopted into `manual` if the user has not moved since. On failure: log, `ErrorJournal`, `manual = appliedManual`, and "That setting could not be applied." from `.control` unless the error is `.noCamera`. With no session (the Simulator) the model's state is the whole of it. `refreshReadouts` leaves `manualRanges` nil while a configure is pending and closes the open control if it lost its scale.

- [ ] **Step 1: Failing tests** in `ManualControlTests`, model as `CaptureFeedbackTests.swift:7-16` builds it, then `refreshReadouts(from: fake)`: `tappingAReadoutOpensItsSliderAndAnotherSwitches` (and nothing is sent); `theFirstMoveLocksBothAndTheReadoutsShowIt`; `autoReturnsBothAndIsSent`; `evCannotBeOpenedOrMovedWhileExposureIsManual` (text `--`, not available); `whiteBalanceTakesTheOtherValueFromTheLiveReadout`; `aBurstWhileOneApplyRunsSendsOnlyTheLatest` (hold, 30 moves, resume: the fake has 2 applies and the last equals `model.manual`); `aFailedApplyReturnsToWhatTheCameraHas` (with the notice); `aClampedValueIsAdopted`; `eachDetentCountsOneHaptic` (3 ISO steps count 3, the same step 0, 4 tint steps inside a ten 0); `aControlChangeNeverReconfiguresBlursOrSaves` (no configure on the fake, `isViewfinderChanging` false, `SavedSelections.load` unchanged, a new model on the same defaults is `.automatic`); `theSimulatorHasRangesAndValues` (every scale exists, no text is `--`, a move changes the text, Auto restores it, `-state scanning` still reads `--`). Update `withoutACameraReadouts…` to the new rule, keeping its press check. `LaunchConfigTests.parsesControlFlag`.
- [ ] **Step 2: Run and see fail.** `scripts/test.sh ManualControlTests`.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the suite, then everything.
- [ ] **Step 5: Commit.** `feat: hold manual controls in the camera model`

### Task 6: What closes the slider and returns the controls to automatic

**Files:** Modify `OpenCam/App/CameraModel.swift` (`phase` gets a `didSet`; `enqueueConfigure` at `:646`; `simulateViewfinderChange` at `:572`; `openRecordSettings`; `apply(_:)`), `CameraModel+Manual.swift`, `CameraModel+Library.swift` (`openLibrary`), `CameraModel+Sweep.swift` (`runSweep`, `openSweep`), `OpenCam/Capture/SessionEvent.swift`, `CameraControlsDelegate.swift`, `CameraSession.swift` (the delegate is made in `init` with the events continuation). Test: `OpenCamTests/ManualLifecycleTests.swift`.

**Interfaces — Produces:** `func resetManual()` (generation up, slider closed, `appliedManual = .automatic`, and if `manual` was not automatic it becomes so and is sent; ranges nil on the device, simulated in the Simulator); `SessionEvent.systemControlsFullscreen`.

| Event | Slider | Values |
|---|---|---|
| Recording starts or stops | stays | stay; applies keep working |
| A configure is queued (lens, mode, format, sound, look); in the Simulator, the configuration changes | closes | automatic; the configure's task first awaits the apply in flight |
| `phase` leaves `.ready` or `.simulator` (camera stopped, media-services reset, rescan, released for the Library) | closes | automatic; the recovery's configure or the session's own restart sets the device |
| The Library opens; a sweep starts | closes | automatic |
| Record settings or the sweep sheet opens; the Camera Control goes full screen | closes | stay |
| Interrupted | closes at the next poll (no ranges) | stay; on `.interruptionEnded` they are sent again with `reapplyingAll: true` |

- [ ] **Step 1: Failing tests.** `recordingKeepsTheSliderAndItsValues` (an apply reaches the fake while `isRecording`; the stop queues no configure); `aCameraChangeReturnsEverythingToAutomaticAndClosesTheSlider` (lens, mode, record selection); `aSliderMovedWhileTheCameraChangesIsNotSent` (configures held, lens selected, a refresh with the fake's old ranges: `toggleControl` and `setControl` are refused and no apply follows the configure); `theConfigureWaitsForTheApplyInFlight` (the fake's `calls` end "manual", "configure"); `theSliderClosesWheneverItsControlCannotBeAdjusted` (stopped camera, Library, sweep, sheet, lost range, `.systemControlsFullscreen`; each ends with `openControl == nil`); `aStoppedCameraComesBackAutomatic`; `anInterruptionKeepsTheValuesAndAppliesThemAgain` (the fake's last apply has `reapplyingAll == true` and equals `model.manual`); `aLibraryClosedBeforeTheReleaseRanLeavesTheCameraAutomatic` (the reset's apply reached the fake).
- [ ] **Step 2: Run and see fail.** `scripts/test.sh ManualLifecycleTests`.
- [ ] **Step 3: Implement** the table. Correct the comment at `CameraControlsDelegate.swift:4-5`.
- [ ] **Step 4: Run** the suite, everything (the recovery, Library and sweep suites must pass unchanged), and the device SDK build.
- [ ] **Step 5: Commit.** `feat: return controls to automatic when the camera changes`

### Task 7: The slider

**Files:** Create `OpenCam/UI/StepSlider.swift`, `ControlSlider.swift`, `ControlAutoButton.swift`, `ControlCloseButton.swift`. Modify `OpenCam/UI/Theme.swift` (`Size.sliderLength = 200`, `Size.sliderThumb = 28`), `CaptureFeedbackModifier.swift`. Test: `OpenCamTests/StepSliderTests.swift`.

**Interfaces — Produces:**

```swift
/// A vertical slider over a fixed number of steps, Theme.Size.minTarget wide. It owns its drag: the thumb moves by the
/// distance dragged from where it was, so a touch alone changes nothing.
struct StepSlider: View {
    let stepCount: Int; let step: Int?; let adjustStride: Int
    let isAutomatic: Bool               // the thumb follows the live value and is drawn dimmed
    let label: String; let valueText: String
    var length = Theme.Size.sliderLength
    let onChange: (Int) -> Void
    static func step(from start: Int, translation: CGFloat, travel: CGFloat, stepCount: Int) -> Int
}
struct ControlSlider: View { let model: CameraModel }       // openSlider into StepSlider; onChange calls setControl
struct ControlAutoButton: View { let model: CameraModel }   // empty for a control with no automatic state
struct ControlCloseButton: View { let model: CameraModel }
```

Accessibility. Slider: `.accessibilityElement()`, label the control's `name`, value its `spoken` text, `.accessibilityAdjustableAction` moving `adjustStride` steps. Auto: text and label "Auto", value "On" or "Off", hints "Returns shutter and ISO to automatic.", "Returns white balance and tint to automatic.", "Returns focus to automatic."; selected while automatic. Close: `xmark`, label "Close slider". Haptic: `CaptureFeedbackModifier` adds `.sensoryFeedback(.selection, trigger: feedback.controlSteps)` (`SwiftUI.swiftinterface:1216`), so VoiceOver's adjust gets it too and it differs from the photo's light impact.

- [ ] **Step 1: Failing tests.** `aDragMovesByDistanceNotToTheFinger` (from step 10 of 21, 50 pt up over 200 pt of travel gives 15); `aTouchAloneChangesNothing`; `aDragStopsAtBothEnds`; `oneStepNeverDividesByZero`.
- [ ] **Step 2: Run and see fail.**
- [ ] **Step 3: Implement.** `DragGesture(minimumDistance: 0)`; the start step is `@State` in `StepSlider`. Track, fill and thumb only; the fill is `Theme.accent` when set by hand and secondary in auto. No background of its own: the strip's pill or the picture's column supplies the glass.
- [ ] **Step 4: Run** everything.
- [ ] **Step 5: Commit.** `feat: add the step slider`

### Task 8: Readout taps and the strip swap on the folded display

**Files:** Create `OpenCam/UI/ControlReadout.swift`, `StripToolbarModifier.swift`, `SliderPlacement.swift`. Modify `OpenCam/UI/ReadoutView.swift` (`isSet`, `isOpen`), `TopReadoutBar.swift`, `PhotoReadoutRow.swift`, `StripToolbar.swift`, `StripControl.swift`, `CameraRootView.swift` (line 24 only), `CameraLayout.swift` (`isFoldedDisplay` moves to the environment). Tests: `OpenCamTests/StripItemsTests.swift`, `SliderPlacementTests.swift`.

**Interfaces — Produces:**

```swift
struct ControlReadout: View { let control: ManualControl; let model: CameraModel; var isCompact = false }
// A plain Button around ReadoutView, disabled when not available. Label: the control's name. Value: "<spoken>, set by hand" or
// "<spoken>, automatic". Hint: "Opens the slider." or "Closes the slider." Selected trait while open.

nonisolated enum SliderPlacement: Sendable, Equatable {
    case strip, picture(edge: HorizontalEdge)
    static func resolve(isFoldedDisplay: Bool, stripEdge: HorizontalEdge?) -> SliderPlacement
    // folded with a strip: .strip; otherwise .picture(edge: stripEdge ?? .trailing)
}
extension EnvironmentValues { var isFoldedDisplay: Bool { get }; var sliderPlacement: SliderPlacement { get } }

// StripToolbar: enum Item { case mode, lens, library, slider, auto, close }; let items: [Item]
//   static func items(open: ManualControl?, isLandscape: Bool) -> [Item]
//   nil: [.mode, .lens, .library]; open: [.slider, .auto, .close], no .auto for .bias; landscape reverses either list.
struct StripToolbarModifier: ViewModifier { let model: CameraModel; let library: LibraryStore?; let isLandscape: Bool }
```

How the swap re-runs only small views: `StripToolbarModifier.body` alone reads `model.openControl`, and only when the placement is `.strip`. It applies `.toolbar { StripToolbar(model:library:items:) }`, whose body is the `ForEach` it is today and reads no model. `StripControl` gains three one-line cases building `ControlSlider`, `ControlAutoButton` and `ControlCloseButton`. Opening, switching or closing re-runs the modifier; a drag changes `manual`, which re-runs `ControlSlider`, `ControlAutoButton` and the `ControlReadout`s. `TopReadoutBar` and `PhotoReadoutRow` no longer read values, so the 4 Hz poll stops re-running them. In `CameraRootView` the modifier takes `.toolbar`'s place on the stack's content and `.onCameraCaptureEvent` stays after it. Open is marked by a short `Theme.accent` bar under the value, set by hand by the value in `Theme.accent`; neither changes the readout's size.

- [ ] **Step 1: Failing tests.** `theStripShowsTheThreeItemsWhenNoControlIsOpen` (replaces the `allCases` test, same intent); `anOpenControlSwapsInSliderAutoAndClose` (portrait, EV, landscape reversed); `SliderPlacementTests`: `theFoldedDisplayUsesTheStrip`, `theOpenDisplayUsesThePictureBesideTheStripOrTheTrailingEdge`.
- [ ] **Step 2: Run and see fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Tap-test on the folded Simulator, portrait then landscape,** reading each control's position from a screenshot first. (1) Tap SHUTTER: the strip shows slider, Auto, close; SHUTTER is marked; the pill stays clear of the clock. (2) Drag up about 90 pt: the value changes, SHUTTER and ISO read as set by hand, the picture is not blurred. (3) Tap ISO: the slider is ISO's. (4) Tap Auto: live values return and Auto reads selected. (5) Tap close: Mode, Lens, Library return. (6) Tap Mode: it switches. (7) Photo, portrait: tap EV and drag (slider and close only, thirds); tap SHUTTER and drag; EV reads `--`, dimmed, and a tap on it opens nothing. (8) `-recording on`: tap ISO and drag. (9) Slider open, tap the format button: Record settings opens; closed, the strip has its three items. (10) Tap the open readout: it closes. Then a burst of screenshots across one open and one close to judge the swap's animation. If the strip does not swap, read `model.openControl` in `StripToolbar.body` as the spike's mode 4 did, and say so in the report.
- [ ] **Step 5: Run** everything. **Commit.** `feat: open a control's slider in the strip from its readout`

### Task 9: The slider inside the picture where the strip is not used

**Files:** Create `OpenCam/UI/PictureSliderColumn.swift`. Modify `OpenCam/UI/CameraLayout.swift` (one overlay), `SliderPlacement.swift`, `OpenCam/App/LaunchConfig.swift`, `OpenCam/UI/CameraRootView.swift` (one environment value). Tests: `SliderPlacementTests`, `LaunchConfigTests`.

**Interfaces — Produces:** `struct PictureSliderColumn: View { let model: CameraModel }` (Auto, slider, close in a `GlassEffectContainer` capsule, drawn only while a control is open); `resolve` gains `isForcedIntoPicture: Bool`; `LaunchConfig.forcesPictureSlider` (`-sliderPlacement picture`, Simulator only, scripted).

- [ ] **Step 1: Failing tests.** `aForcedPlacementUsesThePictureOnTheFoldedDisplay`; `parsesSliderPlacementFlag`.
- [ ] **Step 2: Run and see fail.**
- [ ] **Step 3: Implement.** One overlay on `CameraLayout`'s outer reader, the one that stays inside the safe area, aligned to the placement's edge and centred vertically, `Theme.Space.s` in. It is built only for `.picture`, and `PictureSliderColumn` alone reads the model. No layout file changes. On the open display this is the picture's edge in video and the black margin beside the 3:4 picture in photo.
- [ ] **Step 4: Tap-test with `-sliderPlacement picture` on the folded Simulator,** portrait and landscape, video and photo: tap ISO (the column appears, the strip keeps its three items), drag, Auto, close; then tap Lens and choose another lens with the column open: it closes and the values are automatic. Check the column covers no readout, format button or shutter.
- [ ] **Step 5: Run** everything. **Commit.** `feat: place the slider inside the picture where the strip is not used`

### Task 10: Screenshots and the device checklist

**Files:** Create `docs/screenshots/manual-controls/*.png`. Modify `docs/device-checklist.md`.

- [ ] **Step 1: Folded Simulator screenshots,** each taken after a tap on the readout and one drag, so the slider is open, the thumb moved and the readout marked: `manual-video-v-{shutter,iso,wb,tint}`, `manual-photo-v-{shutter,iso,ev,wb,focus}`, `manual-video-h-{shutter,iso,wb,tint}`, `manual-photo-h-{shutter,iso,wb,tint}`. Per orientation also `…-open-auto` (via `-control iso`, before any drag), `…-after-auto`, `…-closed`, `…-recording` (`-recording on`), and in portrait photo `manual-photo-v-ev-while-manual`. With `-sliderPlacement picture`: `manual-picture-{video,photo}-{v,h}`.
- [ ] **Step 2: Add "Manual controls" to `docs/device-checklist.md`:** each control changes the picture and its readout; no crash at either end of any slider on each of the five lenses; front lenses offer no focus; 24 fps video stops at 1/24 and the clip's `.json` still reads 24 fps; photo at 1 s then 1/60 returns the preview to full rate, and Auto does too; a HEIF taken at a manual 1/1000 in a dim room is as dark as the viewfinder; WB set by hand before and during a ProRes RAW clip is still set after it, and Auto during the clip returns after it; the Camera Control's EV is greyed while exposure is manual; a lens, mode or format change returns every readout to live values; background and return keeps manual values; step haptics are felt in the strip, and whether they are heard in a clip; VoiceOver reads each slider as adjustable in the strip; on the open phone, both orientations, the column appears, drags and clears every control; whether `supportsExposureModeCustom(lensAperture:duration:iso:)` accepts shutter with automatic ISO (Q5).
- [ ] **Step 3: Whole suite and the device SDK build** with 0 warnings. With no control open, compare the four folded camera screens with `docs/screenshots/strip/strip-{video,photo}-{v,h}.png`: only the readout values differ.
- [ ] **Step 4: Commit.** `docs: add manual control screenshots and device checks`

## Not in this plan

- New readouts: EV and FOCUS in video and landscape, TINT in portrait photo (Q1).
- The Camera Control following the open control with its own `AVCaptureSlider` (the spec's "the parameter selected on screen and the one selected on Camera Control stay the same thing"): adding and removing controls is a session configuration change.
- Shutter or ISO alone with the other automatic (Q5).
- A meter in the EV readout while exposure is manual (`exposureTargetOffset`).
- Tap to focus, focus peaking, white balance presets, grey-card white balance.
- Saving manual values, shutter angle, and polish of the system's strip swap animation.
- The strip slider on the open display in landscape (Q2).

## Rulings on the open questions (controller, 2026-11-12)

1. **Controls with no readout in a layout** (EV and focus in video and in landscape; tint in portrait photo): ship as planned. Whether landscape photo takes the photo readout set, and where a focus readout goes in video, are the owner's calls and are asked of him; nothing here depends on the answer.
2. **The open display in landscape has a strip:** the in-picture column is used on the open display in both orientations until it can be tried on the phone. `SliderPlacement.resolve` is the one line to change.
3. **Shutter steps:** third stops, plus the frame rate's own two values in video.
4. **EV range:** the format's system-recommended range when it has one, else the device's limits.
5. **Shutter or ISO alone with the other automatic:** lock both for now. Whether the Duo's formats support the iOS 27 one-sided modes is read on the phone (Task 10's checklist) and decided after.
6. **Direction:** up is more (longer shutter, higher ISO, kelvin and EV, farther focus). Asked of the owner as well; `ManualScale` is the one place to flip it.
