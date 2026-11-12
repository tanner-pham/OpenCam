# Viewfinder Change Blur Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** While the camera changes in a way that pauses the picture (another camera, photo or video, another format), the viewfinder blurs at once and clears when the new picture is live, as Apple's Camera does.

**Architecture:** Every camera change already goes through `CameraModel.enqueueConfigure()`. The model gains one observable flag, `isViewfinderChanging`, raised when a change that pauses the picture is queued and lowered a short settle time after the last queued change has finished. A small overlay on the picture reads the flag and fades a blur material in and out. No capture code changes.

**Tech Stack:** SwiftUI (iOS 27.1), Swift 6, Swift Testing. No new dependencies.

**Spec:** The owner's direction of 2026-11-11: "We should also imitate the apple effect of when we do an action that can freeze the viewfinder, such as changing cameras, recording modes, ect..."

## Global Constraints

- The blur covers the picture only. Readouts, the format button, the shutter and the strip stay drawn and usable, as with the shutter blink.
- The blur starts at the press, before the configure runs, so the pause is never seen bare.
- A change that does not pause the picture shows no blur: the same camera with the same formats and outputs (1x to 2x on the wide camera when nothing else differs).
- The overlay never takes touches and is hidden from accessibility.
- With Reduce Motion on, the blur still shows; it is a cross-fade, not movement.
- `onCameraCaptureEvent` in `CameraRootView` stays where it is (on the NavigationStack's content).
- A photo re-runs only small views today; a camera change must not re-run `ViewfinderArea`'s body or the bottom bar either. Only the overlay reads the flag.
- The timing values are tuning knobs, kept together in one place, because when the first new frame arrives is a property of the phone.

## Review Focus

- Two changes in quick succession (mode, then lens): the blur stays on without a flicker until the last one finishes, and clears once.
- A configure that fails: the blur clears, and the picture is the restored camera's.
- A change refused because a recording is running or the Library holds the camera: no blur, and none left stuck on.
- The mode switch replaces the layout (vertical video and photo are different views): the blur must not pop off and fade in again when the new layout appears.
- A blur stuck on forever would hide a working camera: every path that raises the flag has a path that lowers it.

---

### Task 1: The flag in the model

**Files:**
- Create: `OpenCam/App/ViewfinderChange.swift`
- Modify: `OpenCam/App/CameraModel.swift` (`enqueueConfigure`, `configureFailed`, a new stored property)
- Test: `OpenCamTests/ViewfinderChangeTests.swift`

**Interfaces:**
- Produces:
  - `nonisolated enum ViewfinderChange` with
    - `static func pausesPicture(from previous: SessionConfiguration?, to next: SessionConfiguration) -> Bool`: false when `previous` is nil (the first configure happens behind the scanning screen); true when the mode, the camera (`lens.deviceUniqueID`), `video`, `photo`, `includesAudio` or `needsFrames` differ; false when only the lens's zoom differs.
    - `static let fadeIn: Duration = .milliseconds(120)`, `static let fadeOut: Duration = .milliseconds(300)`, `static let settle: Duration = .milliseconds(150)` (after the configure returns, before the blur starts to clear), `static let simulated: Duration = .milliseconds(400)` (how long a change takes in the Simulator, which has no session).
  - `CameraModel.isViewfinderChanging: Bool` (observed, `private(set)`).
  - `CameraModel.viewfinderSettle: Duration` (`@ObservationIgnored`, default `ViewfinderChange.settle`, shortened by tests, as `confirmationDelay` is).

- [ ] **Step 1: Write the failing tests** in `ViewfinderChangeTests`, using `FakeSessionConfigurator` and the model set-up the recovery and capture feedback tests already use:
  - `aModeChangeBlursAtOnceAndClearsAfterTheConfigure`: after `model.mode = .photo`, `isViewfinderChanging == true` before the fake's configure has run; after `waitForQueuedConfigures()` and the settle, it is false.
  - `twoQuickChangesClearOnce`: change the mode, then the lens to another camera, with the first configure still held; the flag stays true throughout and is false only after the last finishes.
  - `aFailedConfigureClears`: the fake throws; the flag ends false and the selection is the restored one.
  - `aZoomOnlyChangeDoesNotBlur`: `pausesPicture` is false for two configurations that differ only in `lens` where both lenses share `deviceUniqueID`; true for each of: mode, camera, `video`, `photo`, `includesAudio`, `needsFrames`; false for `previous == nil`.
  - `aRefusedChangeDoesNotBlur`: while recording, and while the Library holds the camera, a lens change leaves the flag false.
- [ ] **Step 2: Run them and see them fail.** `scripts/test.sh ViewfinderChangeTests`, expected exit 65 (no `ViewfinderChange`).
- [ ] **Step 3: Implement.** In `enqueueConfigure`, before `requestedConfiguration` is overwritten, raise the flag when `ViewfinderChange.pausesPicture(from: requestedConfiguration, to: configuration)`; it stays raised if a later queued change would not have raised it. When the task of the newest generation ends, by success or failure, wait `viewfinderSettle` and lower the flag if no newer generation was queued meanwhile. A superseded task lowers nothing.
- [ ] **Step 4: The Simulator.** It has no session, so `enqueueConfigure` returns early there. When `isSimulator`, a selection change whose configuration `pausesPicture` relative to the one before raises the flag for `ViewfinderChange.simulated`, then lowers it, so the effect can be seen and screenshot on the stand-in picture. Keep this beside the flag's other code, not in a view.
- [ ] **Step 5: Run the tests, then the whole suite.** `scripts/test.sh ViewfinderChangeTests` exit 0; `scripts/test.sh` exit 0 with totals from the xcresult.
- [ ] **Step 6: Commit.** `feat: flag camera changes that pause the picture`

### Task 2: The blur over the picture

**Files:**
- Create: `OpenCam/UI/ViewfinderChangeBlur.swift`
- Modify: `OpenCam/UI/ViewfinderArea.swift` (one overlay, beneath `ShutterBlinkOverlay`), `OpenCam/UI/CaptureFeedbackModifier.swift` (pass the flag down the way `shutterBlinks` is passed)
- Screenshots: `docs/screenshots/viewfinder-blur/`

**Interfaces:**
- Consumes: `CameraModel.isViewfinderChanging`, `ViewfinderChange.fadeIn`, `ViewfinderChange.fadeOut`.
- Produces: `@Entry var isViewfinderChanging: Bool` (environment, default false); `struct ViewfinderChangeBlur: View`, which alone reads it.

- [ ] **Step 1: Build `ViewfinderChangeBlur`.** A rectangle filled with `.ultraThinMaterial`, opacity 1 while the flag is up and 0 otherwise, animated with ease-out over `fadeIn` on the way in and ease-in-out over `fadeOut` on the way out. Its opacity is derived from the flag, not held in `@State`, so a layout that appears mid-change starts already blurred. `allowsHitTesting(false)`, `accessibilityHidden(true)`.
- [ ] **Step 2: Place it** in `ViewfinderArea` over `picture`, shown in the `.ready` and `.simulator` phases only (the status screens are not a picture).
- [ ] **Step 3: See it in the Simulator.** Folded "OpenCam Dev", portrait and landscape: tap Mode once and take a burst of screenshots (`simctl io ... --display=1`), as was done for the shutter blink. Keep one frame mid-blur for each of: video to photo (portrait), photo to video (portrait), a lens change to the outer front camera (portrait), video to photo (landscape). In each, the picture is blurred and every control is sharp. Take one more two seconds later to show it cleared. Check that 1x to 2x shows no blur.
- [ ] **Step 4: Run the whole suite and compile for the device.** `scripts/test.sh` exit 0 with totals; device SDK build succeeds with 0 warnings.
- [ ] **Step 5: Commit.** `feat: blur the viewfinder while the camera changes`

## Not in this plan

- The flip Apple plays when going between the front and back cameras. The blur alone covers the pause; the flip can follow if wanted.
- Clearing the blur on the first new frame instead of after a fixed settle time. The plain preview has no frame callback today; the settle time is the knob to tune on the phone.
