# OpenCam Control Strip Cleanup

> **For agentic workers:** four small tasks, one commit each. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The folded Duo's control strip holds three things that each do one obvious job: a mode toggle, a lens picker with short labels and icons, and a Library stack. Record settings leaves the strip because the format button already opens it.

**Why:** The owner's direction after using the app on his phone on 2026-11-11, in his words: "Since there is only two recording modes between camera and video, there shouldn't be a button that opens a menu, rather it should just switch and toggle between the two." "Settings doesn't need to be in the control strip since this can be where the resolution and format button is right now, they open the same thing." "The lens option should be a better picker with a predefined list of iPhone lenses that's picked up from the device, right now it spills out with the full name, when we can use icons for this instead, such as the device icon position for inner/outer or a lens icon for the other ones." "We should also make the media library show a stack that feels like a stack of the photo thumbnails (e.g. stacked messy by rotating effect)."

**Spec:** `docs/superpowers/specs/2026-11-09-duo-camera-design.md` (the strip as the camera's control surface). The camera core plan's Global Constraints apply unchanged: Swift 6, no third-party dependencies, system components and system glass, `Theme` for spacing and accent, dark only, all four orientations, no force unwraps or `try!`, one type per file, plain sentence-case copy with no em dashes, conventional commits, no attribution lines.

## Global Constraints

- Branch `feat/strip-cleanup`, stacked on the current top of the stack.
- The strip's items stay native toolbar items (`ToolbarItem(placement: .bottomBar)` with `.axisBehavior(.verticalPreferred)`), each item's content its own small view that reads the model, because a `ToolbarContent` body is not re-run when the model changes.
- `onCameraCaptureEvent` stays on the `NavigationStack`'s content, never on the stack: on the stack it left the strip's items dead to taps on the folded display.
- Every interactive change is TAP-TESTED on the folded simulator "OpenCam Dev" in portrait and landscape, and on the open simulator "Claude Duo camera design" in portrait: one tap, wait two seconds, one `xcrun simctl io <UDID> screenshot` (`--display=1` folded, `--display=3` open), look at it. Screenshots alone are not verification of a control.
- In landscape the order in the strip is reversed, so Mode sits at the bottom, as today.
- Screenshots go to `docs/screenshots/strip/`, names prefixed `strip-`.

## Review Focus

1. Record settings must stay reachable in every state where it was reachable from the strip: both modes, both displays, both orientations, and the stopped-camera state. Pinned by tapping the format button in each, and by `StripItemsTests.recordSettingsIsNoLongerAStripItem` plus the existing `canOpenRecordSettings` tests.
2. The mode toggle must not fire while a recording, a sweep or a scan is in progress. Pinned by `StripItemsTests.theModeToggleIsRefusedWhileModeCannotChange`.
3. A lens whose kind is unknown to the badge table must still get a readable label. Pinned by `LensBadgeTests.anUnknownKindFallsBackToItsLabel`.
4. The Library stack must not load the whole library or decode full-size pictures when a photo is taken. Pinned by `RecentCapturesTests.aNewCaptureDoesNotReloadTheLibrary`.
5. With no captures the Library item still opens the Library and shows the plain symbol. Pinned by `RecentCapturesTests.noCapturesShowsTheSymbol` and a tap.

---

### Task 1: Mode is a toggle; Record settings leaves the strip

**Files:** Modify `OpenCam/UI/StripToolbar.swift` (`Item` loses `record`), `OpenCam/UI/StripControl.swift`, `OpenCam/App/CameraModel.swift` (`func toggleMode()`), `docs/device-checklist.md` (the strip has three items). Test: `OpenCamTests/StripItemsTests.swift`.

**Interfaces — Produces:**

```swift
extension CameraModel {
    /// Photo becomes video and video becomes photo. Does nothing while `canChangeLensOrMode` is false.
    func toggleMode()
}
// StripToolbar.Item: case mode, lens, library
// StripControl .mode: Button { model.toggleMode() } with the CURRENT mode's symbol ("video.fill" / "camera.fill"),
//   accessibility label "Mode", value "Video" or "Photo", hint "Switches to photo." / "Switches to video.",
//   disabled while !model.canChangeLensOrMode.
```

- [ ] **Step 1: Failing tests** — `StripItemsTests`: `recordSettingsIsNoLongerAStripItem` (`StripToolbar.Item.allCases == [.mode, .lens, .library]`); `theModeToggleSwitchesBetweenTheTwoModes` (video, toggle, photo, toggle, video; the selection for each mode is the one that mode had before); `theModeToggleIsRefusedWhileModeCannotChange` (while recording, sweeping and scanning the mode is unchanged; use the existing tests' ways of putting the model in those states).
- [ ] **Step 2: Run to see them fail.** `scripts/test.sh StripItemsTests`.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run to see them pass**, then tap on the folded simulator, portrait and landscape: one tap on Mode switches to photo with no menu, the symbol changes, a second tap switches back; the format button opens Record settings in both modes. Same two checks on the open simulator in portrait.
- [ ] **Step 5: Screenshots** `strip-video-v`, `strip-photo-v`, `strip-video-h`, `strip-photo-h` (folded). **Commit** `feat: make mode a toggle and take record settings out of the strip`.

### Task 2: Lens labels and icons

**Files:** Create `OpenCam/Capability/LensBadge.swift`. Modify `OpenCam/UI/StripControl.swift`. Test: `OpenCamTests/LensBadgeTests.swift`.

**Interfaces — Produces:**

```swift
/// How a lens is shown in the strip and in its menu.
nonisolated struct LensBadge: Sendable, Equatable {
    var shortText: String?        // "0.5x", "1x", "2x" for back lenses; nil when the strip shows only a symbol
    var symbol: String?           // an SF Symbol name for the front cameras; nil for back lenses
    var menuTitle: String         // "Ultra wide", "Wide", "Wide, 2x crop", "Front, outer display", "Front, inner display"
    static func make(for lens: Lens) -> LensBadge
}
```

Rules: back lenses keep their zoom text and get no symbol in the strip (an icon alone cannot tell 0.5x, 1x and 2x apart). The outer front camera gets a symbol of the folded phone and the inner front camera a symbol of the open phone. Take the symbol names from what this SDK really has: check candidates with `UIImage(systemName:)` in a test and pick the closest pair that exists (look for foldable or Duo device symbols first; if the SDK has none, use two clearly different existing device symbols and say which in the report). A lens kind the table does not know shows its own `label` as text. The menu lists every lens the device scan found, in the scan's order, each row a `Label(menuTitle, systemImage:)` with the zoom text in the title for back lenses.

- [ ] **Step 1: Failing tests** — `LensBadgeTests`: `backLensesKeepTheirZoomText`, `frontCamerasShowASymbolAndNoLongName` (the strip text is nil and the symbol exists in this SDK: `UIImage(systemName:) != nil`), `anUnknownKindFallsBackToItsLabel`, `menuTitlesAreShortAndDistinct` (five lenses of the device's kinds give five different titles, none longer than 24 characters).
- [ ] **Step 2–4:** fail, implement, pass; then tap Lens on the folded simulator in both orientations: the menu opens with five short rows (launch with whatever the Simulator fixture offers; say in the report which kinds it has), choosing one changes the strip item.
- [ ] **Step 5: Screenshots** `strip-lens-menu-v`, `strip-lens-menu-h`. **Commit** `feat: show lenses with short labels and device symbols`.

### Task 3: The Library item is a stack of recent thumbnails

**Files:** Modify `OpenCam/UI/LibraryThumbnail.swift`, `OpenCam/App/CameraModel.swift` and `CameraModel+Library.swift` (a short list of the most recent captures). Create `OpenCam/UI/ThumbnailStack.swift`. Test: `OpenCamTests/RecentCapturesTests.swift`.

**Interfaces — Produces:**

```swift
extension CameraModel {
    /// The newest captures, newest first, at most three. Updated when a capture finishes and when the Library closes.
    var recentCaptures: [URL] { get }
}
/// Up to three small thumbnails drawn as a loose stack: the newest on top and upright, the ones beneath turned
/// by -8 and +6 degrees and offset by a couple of points, each with a thin light edge. One capture draws one thumbnail.
struct ThumbnailStack: View { let thumbnails: [CGImage] }
```

Rules: the stack fits the same square the single thumbnail uses today and never grows the strip item. Thumbnails come from the existing `ThumbnailCache` path, so an edited photo's thumbnail shows its edit. Taking a photo must not reload the library or decode a full-size picture: the new capture's thumbnail is made from its own file as today and pushed onto the list. With no captures the item shows the plain photo symbol as today. The whole item is still one button that opens the Library.

- [ ] **Step 1: Failing tests** — `RecentCapturesTests`: `theNewestThreeAreKeptNewestFirst`, `aNewCaptureDoesNotReloadTheLibrary` (count library reloads with the existing test double or a counter), `closingTheLibraryRefreshesTheList` (a photo deleted in the Library leaves the list), `noCapturesShowsTheSymbol`.
- [ ] **Step 2–4:** fail, implement, pass; then on the folded simulator launch with `-seedSamples on`, look at the stack in both orientations, and tap it: the Library opens.
- [ ] **Step 5: Screenshots** `strip-stack-v`, `strip-stack-h`, and one with a single capture. **Commit** `feat: draw the library item as a stack of recent thumbnails`.

### Task 4: Feedback when a photo is taken and when recording starts and stops

The owner, 2026-11-11: "Add a shutter effect or some sort of haptic effect for when a picture is taken or when video starts and stop".

**Files:** Create `OpenCam/UI/ShutterBlink.swift`, `OpenCam/App/CaptureFeedback.swift`. Modify `OpenCam/App/CameraModel.swift` and `CameraModel+Recording.swift` (a counter per event), `OpenCam/UI/ViewfinderArea.swift` (the blink over the picture only), the root view (the haptics), `OpenCam/Capture/CameraSession.swift` only if the audio session must allow haptics while the microphone is live. Test: `OpenCamTests/CaptureFeedbackTests.swift`.

**Interfaces — Produces:**

```swift
/// What just happened, for the views that give feedback. Each value changes exactly once per event.
nonisolated struct CaptureFeedback: Sendable, Equatable {
    var photosTaken = 0        // a photo request was made (not: the press was refused)
    var recordingsStarted = 0  // a recording actually began
    var recordingsStopped = 0  // a recording ended, for any reason
}
extension CameraModel { var feedback: CaptureFeedback { get } }
/// The viewfinder goes dark for about a tenth of a second and comes back: opacity 0 to 1 in 0.04 s, back to 0 in 0.12 s.
struct ShutterBlink: View { let trigger: Int }
```

Rules: the blink covers the picture only, never the controls or the strip, and never blocks touches (`allowsHitTesting(false)`). Haptics through SwiftUI's `sensoryFeedback(_:trigger:)`: a light impact for a photo, a firmer one when recording starts, and a different one when it stops (take the cases from the SDK's `SensoryFeedback`, never from memory; if `.start` and `.stop` exist on iOS use them, else two impact weights). A press that is refused (camera not ready, no space, the Library open) gives no feedback. A recording that ends by itself (storage full, an interruption) still gives the stop feedback. While the microphone is live iOS mutes haptics unless the audio session allows them: read `AVAudioSession.setAllowHapticsAndSystemSoundsDuringRecording` in the SDK and, if video mode would otherwise be silent, allow it where the session's audio is set up; say in the report what you found. The system already plays its own shutter and record sounds; add no sound.

- [ ] **Step 1: Failing tests** — `CaptureFeedbackTests`, with the fake configurator: `aPhotoRequestCountsOnceAndARefusedPressDoesNot`, `aRecordingCountsItsStartAndItsStop`, `aRecordingThatEndsByItselfStillCountsItsStop`, `quickPressesEachCount`.
- [ ] **Step 2–4:** fail, implement, pass. In the Simulator the capture button does nothing for a photo (no camera), so show the blink through a launch flag `-shutterDemo on` that fires it once a second, screenshot it mid-blink, and say plainly that haptics cannot be felt in the Simulator.
- [ ] **Step 5: Commit** `feat: blink the viewfinder and tap the hand on capture, record start and stop`.

**After the four tasks:** full `scripts/test.sh`, the device SDK compile, and a pixel look at the four camera screens against `docs/screenshots/qa/qa-outer-*.png`: only the strip may differ.

**On the phone** (owner): the mode toggle, the lens menu with the phone's five lenses, the stack after three photos, the Camera Control still firing, the blink and the three haptics, and whether the start haptic can be heard in a clip's audio.
