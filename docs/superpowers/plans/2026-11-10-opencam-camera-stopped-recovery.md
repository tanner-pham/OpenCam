# OpenCam: Recover When the Camera Stops

> **For agentic workers:** one task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A camera session that stops with a runtime error never leaves the app unusable. The app goes back to a selection that works, or says the camera stopped while every control needed to get out of it still works.

**Why:** Seen on the owner's iPhone Duo on 2026-11-10. The session posted `AVCaptureSession.runtimeErrorNotification` (`AVFoundationErrorDomain -11800`) about 0.3 s after launch. The app showed "The camera stopped." and nothing else worked: Record settings is disabled without a running camera, a lens or mode change configures the session but never starts it again, and the selection that failed is saved and restored on the next launch. An earlier launch of the same build ran for four minutes, so the trigger is probably a selection the phone accepts at configure time and refuses once it runs. The trigger is not confirmed; this plan fixes the dead end whatever it is.

**Spec:** `docs/superpowers/specs/2026-11-09-duo-camera-design.md` (anti-goal: "A control that names a format or tool the device cannot actually use at that moment."). The camera core plan's Global Constraints apply unchanged (`docs/superpowers/plans/2026-11-09-duocam-camera-core.md`): Swift 6, no third-party dependencies, no force unwraps or `try!`, one type per file, errors as `[Module:Function] Description — {context}`, no new `@unchecked Sendable`, no `nonisolated(unsafe)`, no `@preconcurrency import`, plain sentence-case copy with no em dashes, conventional commits, no attribution lines. API facts only from `docs/research/capture-apis.md` or the SDK headers.

## Global Constraints

- Branch `fix/camera-stopped-recovery`, stacked on `fix/raw-photo-preset`.
- A media-services reset (`AVError.Code.mediaServicesWereReset`) keeps its existing recovery (`restartAfterMediaServicesReset`, the `.restarted` event). Nothing here changes it.
- No loop: one runtime error leads to at most one automatic recovery attempt. A second runtime error before that attempt is confirmed ends in the stopped state.
- Exact UI copy: the stopped state keeps "The camera stopped."; its button is "Try again"; the notice after an automatic recovery is the existing `formatFailedNotice` ("That format could not be used.").
- While recording, sweeping or scanning, the existing handling stands: a runtime error during a recording still ends the clip as today, and the recovery below runs after that.

## Review Focus

1. A selection that fails once it runs must not survive a relaunch as the saved selection. Pinned by `CameraStoppedTests.aSelectionThatStopsTheCameraAtLaunchIsReplacedByTheDefault`.
2. The stopped state must leave a way out. Pinned by `CameraStoppedTests.theStoppedStateKeepsRecordSettingsAndRetryUsable`.
3. Recovery must not loop. Pinned by `CameraStoppedTests.aSecondStopDuringRecoveryEndsInTheStoppedState`.
4. A runtime error on a confirmed, long-running configuration (a real fault, not a bad selection) must not silently change the user's selection. Pinned by `CameraStoppedTests.aStopOnAConfirmedSelectionRestartsItOnceWithoutChangingIt`.
5. A media-services reset must behave exactly as before. Pinned by the existing reset tests, unchanged.

---

### Task 1: Recover from a stopped camera

**Files:**
- Create: `OpenCam/App/CameraModel+Recovery.swift`
- Modify: `OpenCam/App/CameraModel.swift` (`apply(.runtimeError)` calls the recovery; `canOpenRecordSettings`; whatever state the recovery needs), `OpenCam/Capture/CameraSession.swift` (the runtime error message also carries the underlying error, `NSUnderlyingErrorKey`, domain and code, and the lens and mode of the applied configuration; nothing else), the view that draws the failed message (a "Try again" button for the stopped state only; find it from `phase` in `OpenCam/UI/`)
- Test: `OpenCamTests/CameraStoppedTests.swift`

**Interfaces:**
- Consumes: `CameraModel.apply(_ event: SessionEvent)`, `SessionEvent.runtimeError(String)`, `.restarted`, `enqueueConfigure()`, `configureFailed`, `lastWorking`, `requestedConfiguration`, `currentSelection`, `persist()`, `show(_:from:)`, `formatFailedNotice`, `SessionConfigurator` (`configure`, `start`), `FakeSessionConfigurator` in the tests, `CameraPhase.failed(String)`.
- Produces:

```swift
extension CameraModel {
    static let cameraStopped = "The camera stopped."
    /// True in the stopped state: `phase == .failed(cameraStopped)` with a session attached.
    var isCameraStopped: Bool { get }
    /// How long a configuration must run without a runtime error before it counts as confirmed.
    static let runningConfirmation: Duration   // .milliseconds(1500)
    /// Called for every runtime error that is not a media-services reset. See the rules below.
    func cameraStopped(_ message: String)
    /// The stopped state's "Try again": configures the current selection again and starts the session.
    func retryCamera()
}
// CameraModel.canOpenRecordSettings is also true while isCameraStopped (and not recording or sweeping), when the
// capabilities are not empty.
```

Rules for `cameraStopped`, in order. "Confirmed" means the session ran that configuration for `runningConfirmation` after the configure that applied it, with no runtime error in between; the model remembers the last confirmed configuration and its selection.
1. The message is logged, as today.
2. If an automatic recovery is already in flight and not yet confirmed: the phase becomes `.failed(cameraStopped)`. Stop.
3. If the configuration that was running is NOT the confirmed one and a confirmed one exists (the user just changed something and it failed): restore the confirmed selection the way `configureFailed` restores `lastWorking`, show `formatFailedNotice` from `.configuration`, configure it and start the session again. This is the one automatic recovery.
4. If nothing is confirmed yet (the failure came at launch) and the current selection is not the default selection for the default lens: select the default (the same values a first launch picks), persist it, configure it and start the session. This is the one automatic recovery, with the same notice.
5. Otherwise (the confirmed configuration itself stopped, or the default failed at launch): configure the same configuration again and start the session once, without changing the selection and without a notice. This is the one automatic recovery.
6. When the recovery's configure or start throws, or rule 2 fires: the phase is `.failed(cameraStopped)`.
7. A recovery that then runs for `runningConfirmation` is confirmed: the phase is `.ready`, the configuration and selection become the confirmed ones.

In the stopped state: Mode, Lens and Record settings work; any selection change configures AND starts the session, and a configuration that then runs for `runningConfirmation` returns the phase to `.ready`; `retryCamera()` does the same for the unchanged selection. The capture button stays disabled until the phase is `.ready`.

- [ ] **Step 1: Write the failing tests** in `OpenCamTests/CameraStoppedTests.swift`, using the suite style and helpers of `OpenCamTests/CameraModelEventTests.swift` (`attachedModel`, `FakeSessionConfigurator`). Make the confirmation delay injectable for tests in the smallest way (for example a stored `runningConfirmation` the test sets to a few milliseconds), never by sleeping for 1.5 s. Required tests, each asserting the phase, the selection, the notice, what the fake was asked to configure and how many times it was started:
  - `aSelectionThatFailsOnceRunningGoesBackToTheConfirmedOne` (rule 3): confirm a first configuration; change the record selection; deliver `.runtimeError` before the new one is confirmed; the selection, the fake's last applied configuration and the saved selections are the first one's; the notice is "That format could not be used."; after the confirmation delay the phase is `.ready`.
  - `aSelectionThatStopsTheCameraAtLaunchIsReplacedByTheDefault` (rule 4, Review Focus 1): saved selections hold a non-default record selection; attach; deliver `.runtimeError` before anything is confirmed; the selection and the saved selections are the default; the fake applied the default configuration and was started again; after the delay the phase is `.ready`.
  - `aStopOnAConfirmedSelectionRestartsItOnceWithoutChangingIt` (rule 5, Review Focus 4): confirm; deliver `.runtimeError`; the selection is unchanged, no notice, the fake applied the same configuration again and was started; after the delay the phase is `.ready`.
  - `aSecondStopDuringRecoveryEndsInTheStoppedState` (rule 2, Review Focus 3): as the first test, then a second `.runtimeError` before the recovery is confirmed; the phase is `.failed("The camera stopped.")`; the fake was not asked to configure a third time.
  - `theStoppedStateKeepsRecordSettingsAndRetryUsable` (Review Focus 2): reach the stopped state; `canOpenRecordSettings` and `canChangeLensOrMode` are true and `canCapture` is false; a record selection change makes the fake configure and start; after the delay the phase is `.ready`. Reach the stopped state again; `retryCamera()` does the same.
  - `aRecoveryWhoseConfigureThrowsEndsInTheStoppedState` (rule 6).
  - The existing media-services reset tests pass unchanged.
- [ ] **Step 2: Run to see them fail** — `scripts/test.sh CameraStoppedTests`. Expected: build errors for the missing names.
- [ ] **Step 3: Implement to the Interfaces and rules.** Keep the recovery in `CameraModel+Recovery.swift`; change `CameraModel.swift` only where the rules need it.
- [ ] **Step 4: Run to see them pass** — `scripts/test.sh CameraStoppedTests`, `scripts/test.sh CameraModelEventTests`, the full `scripts/test.sh` (326 passing before this task; none removed or weakened), then the device SDK compile from the camera core plan. Expected: `** BUILD SUCCEEDED **`, 0 warnings.
- [ ] **Step 5: Screenshot** — the stopped state on the folded simulator in both orientations, with its "Try again" button, through a launch flag if one exists for the failed state (`-state`), else say in the report that no flag reaches it and attach none. Look at each.
- [ ] **Step 6: Commit**

```bash
git add OpenCam OpenCamTests docs/screenshots
git commit -m "fix: recover when the camera session stops instead of leaving the app dead"
```

**On the phone** (controller and owner):
- [ ] With the selection that stopped the camera still saved, launch: the camera comes up on the default selection with "That format could not be used.".
- [ ] Choose the failing combination again in Record settings: the camera returns to the previous one with the same notice, and Record settings still opens.
