# OpenCam Editor Local Tools Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the photo editor undo and redo, local masks (linear, radial, brush with finger and Apple Pencil, subject) that each carry their own light and colour adjustments, and a clean-up pass over the editor and Library UI on the folded display.

**Architecture:** Masks belong to one photo's edit (`PhotoEdit.masks`, edit file version 3), never to a look, so the viewfinder and look tiles are untouched. The renderer applies the global colour table, then each mask's own colour table blended in through a grayscale mask image, then the spatial effects; the preview, export and thumbnails all render the whole edit. Undo is a time-coalesced history of whole edits in `EditorModel`.

**Tech Stack:** SwiftUI, Swift 6 (default actor isolation MainActor), Core Image, Vision (`GenerateForegroundInstanceMaskRequest`), UIKit touches for the brush, Swift Testing. iOS 27.1+, Xcode 27.2.

**Spec:** No separate spec file. The brief is Tanner's original feature list as relayed on 2026-11-12 by the parent session ("iPhone Duo sensor access in third-party apps"), under an overnight autonomous grant: masks (linear, radial, brush) each with their own adjustments; subject masking by on-device segmentation; Apple Pencil touch-ups with pressure and a finger fallback; spot healing; RAW development from the DNG; undo and redo; and "clean up the UI as much as possible". Rulings made without him are provisional and listed in the PR.

**Not in this plan, and why:** spot healing (no system healing filter; a patch-match fill is its own project) and RAW development from the DNG (the Simulator cannot produce a DNG to build and check `CIRAWFilter` against; needs files from the phone). Both stay on the plan's "Later work" list.

## Global Constraints

- Work only in the worktree `/Users/tannerpham/CS Projects/DuoCam/.claude/worktrees/editor-local-tools`, branch `tannerpham/editor-local-tools` (stacked on `tannerpham/editor-colour-tools-eb9e9a`, PR 9).
- Fence: do not change `OpenCam/App/CameraModel*.swift`, `OpenCam/Capture/`, `OpenCam/Capability/`, the camera screen's views in `OpenCam/UI/` (strip, layouts, viewfinder, bottom bar, Record settings) or `OpenCam/App/OpenCamApp.swift`. `OpenCam/App/LaunchConfig.swift` only for a launch flag, in its own commit.
- No third-party dependencies, no new packages. No `as!`, `try!` or force unwraps in app code. Model and render types are `nonisolated` like their neighbours.
- Every one of the 420 existing tests stays. A test that hard-codes something this plan changes (a group title list, edit version 2, a closure type) is updated to the new value, never deleted or loosened.
- Tests: `OPENCAM_SIM_NAME="OpenCam Dev B" scripts/test.sh <SuiteName>`. The script always exits 0; read the result from the newest bundle: `xcrun xcresulttool get test-results summary --path "$(ls -td .build/Logs/Test/*.xcresult | head -1)"` (`failedTests` must be 0). Use only the simulator "OpenCam Dev B"; never `booted`.
- User-facing copy: plain and functional, no em dashes, no claims the feature does not keep. Log lines: `[Type:function] Description — {context}` as the existing code does.
- The original photo is never written. Looks never carry masks. Commits: conventional, atomic, no attribution lines. Implementers commit; only the controller pushes.
- Screenshots for this branch go in `docs/screenshots/e4/`.

## Review Focus

1. A version 3 edit opened by the PR 9 build: it must open read-only (the existing newer-version path), never drop the masks on save. Pinned by Task 2's `savedEditIsVersionThree` and the existing newer-version tests.
2. Degenerate mask geometry (linear start equal to end, radial radius 0, a brush mask with no strokes, a subject mask with no subject found): it must render as if the mask were absent, with no crash and no black or NaN pixels. Pinned in Task 3.
3. The shared picture must match the screen: export and Library thumbnails render the masks too. Pinned in Task 3 (exporter and thumbnail key tests).
4. Looks and masks: saving a look keeps only the global values; applying a look leaves the photo's masks; Reset all clears them. Pinned in Task 4.
5. Undo granularity: one slider drag, one brush stroke, one look tap, one Reset all and one mask added or deleted are each one undo step. Pinned in Tasks 1, 4 and 6.

---

### Task 1: Undo and redo

**Files:**
- Create: `OpenCam/Edit/EditHistory.swift`
- Modify: `OpenCam/UI/Editor/EditorModel.swift`, `OpenCam/UI/Editor/EditorView.swift` (toolbar)
- Test: `OpenCamTests/EditHistoryTests.swift`; add to `OpenCamTests/EditorModelTests.swift`

**Interfaces:**
- Produces: `nonisolated struct EditHistory: Sendable` with `static let coalesceWindow: TimeInterval = 0.6`, `static let limit = 100`, `mutating func record(_ before: PhotoEdit, at time: Date)`, `mutating func undo(from current: PhotoEdit) -> PhotoEdit?`, `mutating func redo(from current: PhotoEdit) -> PhotoEdit?`, `mutating func clear()`, `var canUndo: Bool`, `var canRedo: Bool`.
- Produces on `EditorModel`: `var currentEdit: PhotoEdit` (the edit as shown; Task 4 adds masks to it), `private func restore(_ edit: PhotoEdit)`, `func undo()`, `func redo()`, `var canUndo: Bool`, `var canRedo: Bool`, init parameter `now: (@Sendable () -> Date)? = nil` (test seam; `Date.init` otherwise).

Rules: `record` pushes `before` and clears redo unless the previous `record` was less than `coalesceWindow` earlier, in which case it only moves the time on (so a drag is one step). `undo`/`redo` end the current step, so the next change always starts a new one. Beyond `limit` the oldest step is dropped. Every change to `adjustments` or `lookName` that is not a restore records the edit as it was before the change; loading a photo clears the history.

- [ ] **Step 1: Write the failing tests** in `EditHistoryTests`: `undoRestoresTheEditBeforeAChange` (record a at t0, undo from b gives a, redo from a gives b); `changesInsideTheWindowAreOneStep` (record a, b, c at t0, t0+0.3, t0+0.5; undo from d gives a; then `canUndo` is false); `changesApartAreTwoSteps` (a at t0, b at t0+1; undo from c gives b, then a); `aNewChangeClearsRedo`; `theOldestStepGoesPastTheLimit` (101 records 1 s apart allow exactly 100 undos); `undoEndsTheStep` (record a at t0, undo, record x at t0+0.1: `canUndo` is true). In `EditorModelTests`, with an injected clock: `undoTakesASliderDragBackInOneStep` (exposure 10, 20, 30 within 0.6 s; undo gives 0; redo gives 30) and `applyingALookIsOneUndoStep` (undo restores both the adjustments and the look name).
- [ ] **Step 2: Run them to see them fail.** `scripts/test.sh EditHistoryTests` and `EditorModelTests`: build errors for the missing type.
- [ ] **Step 3: Implement** `EditHistory` and the model members. The toolbar gains, before Export, `Button("Undo", systemImage: "arrow.uturn.backward")` with `.keyboardShortcut("z")` and `Button("Redo", systemImage: "arrow.uturn.forward")` with `.keyboardShortcut("z", modifiers: [.command, .shift])`, each disabled when it cannot act or the photo failed to load.
- [ ] **Step 4: Run them to see them pass,** then the whole suite once.
- [ ] **Step 5: Screenshot** `e4-undo-v` and `e4-undo-h` (portrait and landscape, editor on Light after one slider move, built with `SHOT_DIR=docs/screenshots/e4 OPENCAM_SIM_NAME="OpenCam Dev B" scripts/shot.sh <name> -orientation <o> -screen editor -seedSamples on -editorGroup light`). Pass when Undo and Redo show without colliding with Export, Reset all or Done; report where the system placed them.
- [ ] **Step 6: Commit** `feat: undo and redo edits in the editor`.

### Task 2: Local masks in the edit file

**Files:**
- Create: `OpenCam/Edit/LocalMask.swift`
- Modify: `PhotoEdit` (its file under `OpenCam/Edit/`)
- Test: `OpenCamTests/LocalMaskTests.swift`

**Interfaces:**
- Produces:
  - `nonisolated struct MaskPoint: Codable, Sendable, Hashable { var x: Double; var y: Double }` (picture coordinates, 0...1 from the top left).
  - `nonisolated struct BrushDab: Codable, Sendable, Hashable { var x: Double; var y: Double; var radius: Double }` (radius as a fraction of the picture's shorter side).
  - `nonisolated struct BrushStroke: Codable, Sendable, Hashable { var dabs: [BrushDab]; var isErasing = false }`.
  - `nonisolated enum MaskShape: Codable, Sendable, Hashable` with `case linear(start: MaskPoint, end: MaskPoint)` (full effect at `start`, none at `end`), `case radial(centre: MaskPoint, radius: Double, feather: Double)` (radius a fraction of the shorter side; full effect inside `radius * (1 - feather)`, none beyond `radius`), `case brush(strokes: [BrushStroke])`, `case subject`; `var kind: MaskKind`.
  - `nonisolated enum MaskKind: String, CaseIterable, Sendable { case linear, radial, brush, subject }` with `title` "Linear", "Radial", "Brush", "Subject" and `var defaultShape: MaskShape`: linear start (0.5, 0.0) end (0.5, 0.5); radial centre (0.5, 0.5), radius 0.3, feather 0.5; brush no strokes; subject.
  - `nonisolated struct LocalMask: Codable, Sendable, Hashable, Identifiable { var id = UUID(); var shape: MaskShape; var isInverted = false; var adjustments = Adjustments() }` with `static let keys: [AdjustmentKey] = [.exposure, .contrast, .highlights, .shadows, .temperature, .tint, .saturation]`.
  - `PhotoEdit`: `static let currentVersion = 3`, `var masks: [LocalMask] = []`, init gains `masks: [LocalMask] = []`, `masks` decoded when present (else `[]`) and encoded only when not empty; `isIdentity` also needs `masks.isEmpty`.

- [ ] **Step 1: Write the failing tests:** `anEditWithEveryKindOfMaskRoundTrips` (one mask of each kind, an inverted one, a brush with an erasing stroke; encode then decode is equal); `aVersionTwoFileOpensWithNoMasks` (`{"adjustments":{"exposure":10},"version":2}` decodes with `masks == []` and exposure 10); `anEditWithAMaskIsNotIdentity` (a mask with no adjustments still counts); `anEditWithoutMasksWritesNoMasksKey`; `savedEditIsVersionThree` (save through `EditStore`, read the JSON, `version` is 3); `maskKindTitlesAndDefaults`.
- [ ] **Step 2: Run** `scripts/test.sh LocalMaskTests`: fails to build.
- [ ] **Step 3: Implement.** Update any existing test that hard-codes version 2 to `PhotoEdit.currentVersion`, and name each one in the report.
- [ ] **Step 4: Run** `LocalMaskTests`, `EditStoreTests`, `LookStoreTests`: all pass.
- [ ] **Step 5: Commit** `feat: store local masks in the edit file as version 3`.

### Task 3: Masks in the render pipeline

**Files:**
- Create: `OpenCam/Render/MaskImage.swift`
- Modify: `OpenCam/Render/LookRenderer.swift`, `OpenCam/Render/ColourCubeCache.swift`, `OpenCam/Render/PhotoExporter.swift`, `OpenCam/Library/ThumbnailCache.swift`, `OpenCam/UI/Editor/EditorModel.swift`
- Test: `OpenCamTests/MaskRenderTests.swift`; update the one `renderPreview:` closure in the existing tests to the new type

**Interfaces:**
- Consumes: Task 2's types.
- Produces:
  - `nonisolated enum MaskImage { static func image(for mask: LocalMask, extent: CGRect, subject: CIImage?) -> CIImage? }`: a grayscale image over `extent`, white where the mask's adjustments apply fully, inverted when `isInverted`; nil when the mask cannot apply (degenerate geometry, a brush with no painted dabs, a subject mask without a subject). Geometry values are clamped here, the one place they are read: coordinates to -1...2, radius 0.001...4, feather 0...1, dab radius 0.001...0.5.
  - `LookRenderer.render(_ image: CIImage, edit: PhotoEdit, subject: CIImage? = nil) -> CIImage` and `renderedCGImage(_:edit:subject:) async -> CGImage?`. `render(_:adjustments:)` stays and equals `render(_:edit:)` with no masks, so look tiles and the viewfinder do not change.
  - `ColourCubeCache.init(capacity: Int = 1, build:)`, least recently used; the renderer keeps a second cache with capacity 8 for mask tables.
  - `EditorModel`: renders `currentEdit` (`RenderCoalescer<PhotoEdit>`); the `renderPreview` seam becomes `(CIImage, PhotoEdit) async -> CGImage?`; `renderedAdjustments` stays, read from a new `renderedEdit: PhotoEdit?`.

Pipeline order: global colour table, then for each mask with colour changes its own table applied to the result so far and blended back through `MaskImage` (`CIBlendWithMask`), then sharpening, noise reduction, grain and vignette as today. Linear: `CILinearGradient` white at `start` to black at `end`. Radial: `CIRadialGradient`, white inside `radius * (1 - feather)` to black at `radius`. Brush: strokes rasterised into a grayscale image whose long side is at most 1024 px (white dabs and segments, round caps; erasing strokes draw black), scaled to `extent` and softened with a small blur. Picture y runs down; Core Image y runs up.

`PhotoExporter.export` renders the whole edit. `ThumbnailCache`'s key hashes the adjustments alone when there are no masks (old keys stay valid) and the adjustments with the masks otherwise; thumbnails render the edit with no subject (a subject mask shows only in the editor and the export; say so in a comment).

- [ ] **Step 1: Write the failing tests** on a flat 100 x 100 grey image, global adjustments identity, one mask with exposure +100, sampling rendered pixels: `linearMaskBrightensFromStartToEnd` (top row brighter by more than 0.1, bottom row within 0.02 of no mask); `radialMaskBrightensTheCentreOnly`; `invertedRadialBrightensTheCornersOnly`; `brushDabBrightensWhereItWasPainted` (dab at (0.25, 0.25) radius 0.1; far corner unchanged); `degenerateMasksRenderAsIfAbsent` (linear start equal to end, radial radius 0, brush with no strokes, subject with no subject image: each pixel-equal to the render without masks, none black or NaN); `aMaskWithNoAdjustmentsChangesNothing`; `renderWithAdjustmentsIsUnchanged` (the old entry point equals `render(edit:)` with no masks); `exportIncludesMasks` (exporter output's top row brighter for a linear mask); `thumbnailKeyChangesWithMasks` (and is unchanged for an edit with no masks); `cubeCacheKeepsEightEntries`.
- [ ] **Step 2: Run** `scripts/test.sh MaskRenderTests`: fails to build.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `MaskRenderTests`, `LookRendererTests`, `PhotoExporterTests`, `ThumbnailCacheTests`, `EditorModelTests` (or the suites by their real names): all pass.
- [ ] **Step 5: Commit** `feat: render local masks in the preview, export and thumbnails`.

### Task 4: The Masks group

**Files:**
- Create: `OpenCam/UI/Editor/MasksPanel.swift`
- Modify: `OpenCam/Edit/EditorGroup.swift` (`case masks` after `effects`, title "Masks", no keys), `OpenCam/Edit/EditorLayout.swift` (`minPanelHeight(for: .masks)` 340), `OpenCam/UI/Editor/EditorPanel.swift`, `OpenCam/UI/Editor/EditorModel.swift`, the `-editorGroup` comment in `LaunchConfig.swift` only if it lists the groups (own commit)
- Test: add to `OpenCamTests/EditorModelTests.swift`; update the group-title list test

**Interfaces:**
- Consumes: Tasks 1-3.
- Produces on `EditorModel`: `var masks: [LocalMask]` (recorded in history and rendered like `adjustments`), `var selectedMaskID: UUID?`, `var selectedMask: LocalMask?`, `func addMask(_ kind: MaskKind)` (appends `kind.defaultShape`, selects it), `func deleteSelectedMask()` (selects the mask before it, or none), `func updateSelectedMask(_ change: (inout LocalMask) -> Void)` (one write to `masks`). `currentEdit`, `restore`, `hasChanges`, `save`, `load` include masks. `resetAll` clears masks and the selection; `applyLook` leaves masks; saving a look stores only the global adjustments.

Panel, top to bottom: four add buttons in one row ("Linear", "Radial", "Brush", "Subject", `.bordered`, at least 44 pt tall); then, once a mask exists, a `ScrollingPicker` of the masks labelled "<kind title> <position from 1>", an "Invert" button carrying `.isSelected` when on, and "Delete" (`role: .destructive`); then the selected mask's seven sliders (`LocalMask.keys`, `AdjustmentSlider`, reset to 0) in the panel's scroll view. With no masks the panel shows "Add a mask to change one part of the photo." under the add row.

- [ ] **Step 1: Write the failing tests:** `addingAMaskSelectsIt`; `deletingAMaskSelectsTheOneBefore`; `aMaskSliderChangesOnlyTheSelectedMask`; `masksAreSavedAndReadBack` (save, new model, load: equal); `resetAllClearsMasks`; `applyingALookKeepsMasks`; `savingALookLeavesMasksOut`; `deletingAMaskIsOneUndoStep`; the group-title test lists "Masks" after "Effects".
- [ ] **Step 2: Run** `EditorModelTests` and `AdjustmentsTests`: fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** them: pass.
- [ ] **Step 5: Screenshots** `e4-masks-empty-v`, `e4-masks-v`, `e4-masks-h` (`-editorGroup masks`, then tap "Linear" and move Exposure). Pass when nothing clips or collides and the picture shows the top brightened.
- [ ] **Step 6: Commit** `feat: add a Masks group with linear, radial, brush and subject masks`.

### Task 5: Handles on the picture and the mask overlay

**Files:**
- Create: `OpenCam/Edit/MaskGeometry.swift`, `OpenCam/UI/Editor/MaskHandles.swift`
- Modify: `OpenCam/UI/Editor/EditorPicture.swift`, `OpenCam/UI/Editor/MasksPanel.swift`, `OpenCam/UI/Editor/EditorModel.swift`, `OpenCam/Render/LookRenderer.swift`
- Test: `OpenCamTests/MaskGeometryTests.swift`

**Interfaces:**
- Consumes: Task 4's model API.
- Produces: `nonisolated enum MaskGeometry` with `static func point(_ location: CGPoint, in size: CGSize) -> MaskPoint` (clamped to 0...1), `static func location(_ point: MaskPoint, in size: CGSize) -> CGPoint`, `static func radius(from centre: MaskPoint, to point: MaskPoint, in size: CGSize) -> Double` (distance over the shorter side). `EditorModel.isShowingMaskOverlay: Bool` and `maskOverlay: CGImage?` (the selected mask in translucent red at the proxy's size, redrawn when the selected mask or the toggle changes). `LookRenderer.maskOverlay(for: LocalMask, extent: CGRect, subject: CIImage?) -> CIImage?`.

On the fitted picture, only while the Masks group is open and a linear or radial mask is selected: linear shows a line across the picture through `start` and one through `end`, both perpendicular to start-end, with a handle on each point; radial shows its outer circle, a dashed inner circle where the feather begins, a centre handle and an edge handle. Handles are drawn 14 pt and hit-test 44 pt; dragging one moves that point (the centre handle moves the circle). Elsewhere the picture keeps its press-to-show-original. The panel gains "Show mask" (overlay on or off, default on) and, for radial masks, a "Feather" slider 0...100.

- [ ] **Step 1: Write the failing tests:** `pointAndLocationAreInverse`; `pointsOutsideThePictureAreClamped`; `radiusIsMeasuredAgainstTheShorterSide` (in a 200 x 100 size, a point 50 pt right of the centre gives 0.5).
- [ ] **Step 2: Run** `MaskGeometryTests`: fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run:** pass.
- [ ] **Step 5: Screenshots** `e4-mask-linear-v`, `e4-mask-radial-v`, `e4-mask-radial-h` with handles and the overlay. Pass when handles sit on the picture, not under the panel or the toolbar.
- [ ] **Step 6: Commit** `feat: drag linear and radial masks on the picture and show the masked area`.

### Task 6: Brush painting with a finger or Apple Pencil

**Files:**
- Create: `OpenCam/Edit/BrushStrokeBuilder.swift`, `OpenCam/UI/Editor/BrushCanvas.swift`
- Modify: `OpenCam/UI/Editor/EditorPicture.swift`, `OpenCam/UI/Editor/MasksPanel.swift`, `OpenCam/UI/Editor/EditorModel.swift`
- Test: `OpenCamTests/BrushStrokeBuilderTests.swift`; add to `EditorModelTests`

**Interfaces:**
- Consumes: Task 4's model API, Task 5's `MaskGeometry`.
- Produces: `nonisolated struct BrushStrokeBuilder: Sendable` with `init(radius: Double, isErasing: Bool)`, `mutating func add(_ point: MaskPoint, pressure: Double?) -> Bool` (false when the point is closer than a quarter of the current radius to the last dab), `var stroke: BrushStroke`. A dab's radius is `radius * (0.35 + 0.65 * pressure)` with pressure clamped to 0...1; no pressure (a finger) counts as 1. `EditorModel.brushSize: Double` (1...100, default 30, maps linearly to a radius of 0.01...0.15), `isErasing: Bool`, `beginStroke(at: MaskPoint, pressure: Double?)`, `continueStroke(at:pressure:)`, `endStroke()`; the stroke is written into the selected brush mask as it grows, so it renders while painting and is one undo step.

`BrushCanvas` is a `UIViewRepresentable` over the fitted picture, present only when the Masks group is open and a brush mask is selected. It reads each touch's `preciseLocation(in:)` and its coalesced touches; for `touch.type == .pencil` the pressure is `force / maximumPossibleForce`; for a finger, nil. The panel gains a segmented "Paint" / "Erase" picker and a "Size" slider for brush masks.

- [ ] **Step 1: Write the failing tests:** `pressureScalesTheDab` (radius 0.1: pressure 0 gives 0.035, 1 gives 0.1, nil gives 0.1); `closePointsAreSkipped`; `erasingStrokesAreMarked`; in `EditorModelTests`, `aStrokeIsOneUndoStep` and `paintingNeedsABrushMaskSelected` (no change when a linear mask is selected).
- [ ] **Step 2: Run:** fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run:** pass.
- [ ] **Step 5: Screenshots** `e4-brush-v` and `e4-brush-h` after painting a stroke by finger (`touch_path`) with the overlay on.
- [ ] **Step 6: Commit** `feat: paint brush masks with a finger or Apple Pencil pressure`.

### Task 7: Subject masks

**Files:**
- Create: `OpenCam/Render/SubjectMasker.swift`
- Modify: `OpenCam/UI/Editor/EditorModel.swift`, `OpenCam/Render/PhotoExporter.swift`, `OpenCam/UI/Editor/MasksPanel.swift`
- Test: add to `EditorModelTests` and `MaskRenderTests`

**Interfaces:**
- Consumes: Task 3's `render(_:edit:subject:)`, Task 4's model API.
- Produces: `nonisolated enum SubjectMasker { @concurrent static func mask(for image: CIImage) async -> CIImage? }`: Vision `GenerateForegroundInstanceMaskRequest` on the image, all instances, scaled to the image (`generateScaledMask(for:scaledToImageFrom:)` with an `ImageRequestHandler`), as a grayscale `CIImage` over `image.extent`; nil, with a log line, when Vision finds nothing or fails. Check the exact Swift API in `$(xcrun --sdk iphoneos --show-sdk-path)/System/Library/Frameworks/Vision.framework/Modules/Vision.swiftmodule/arm64e-apple-ios.swiftinterface`, not from memory. `EditorModel` gains `subjectState: SubjectState` (`.notNeeded`, `.finding`, `.found`, `.notFound`) and init seam `findSubject: (@Sendable (CIImage) async -> CIImage?)? = nil`; it looks for the subject on the proxy once per open, the first time a subject mask exists, and passes it to every preview render. The exporter finds the subject on the full-size image when the edit has a subject mask.

The panel shows, for a selected subject mask, "Finding the subject…" while `.finding` and "No subject was found in this photo." for `.notFound`.

- [ ] **Step 1: Write the failing tests:** `aSubjectMaskRendersWithTheFoundSubject` (seam returns a white-left, black-right mask; the left half brightens); `noSubjectFoundLeavesThePhotoUnchanged` (seam returns nil; preview equals no mask; state `.notFound`); `theSubjectIsFoundOncePerOpen` (two subject masks, one seam call).
- [ ] **Step 2: Run:** fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run:** pass. Then try a real subject mask on "OpenCam Dev B" with a seeded photo and report what Vision returned there; if it fails on the Simulator, say so and leave the device check to Tanner.
- [ ] **Step 5: Commit** `feat: mask the photo's subject with on-device segmentation`.

### Task 8: UI clean-up on the folded display

**Files:**
- Modify: files under `OpenCam/UI/Editor/` and `OpenCam/UI/Library/` only (the fence holds)
- Test: whichever existing tests a change touches

- [ ] **Step 1: Audit.** Screenshot every editor group (Light, Colour, Curve, Mix, Grading, Masks, Detail, Effects, Looks) and the Library, folded portrait and landscape, at the default text size and at accessibility extra large (`xcrun simctl ui <Dev B UDID> content_size accessibility-extra-large`, reset with `large` afterwards). List everything that clips, collides, truncates or looks unlike its neighbours, with the screenshot it is in. Known items: the grading wheel's Luminance label truncates at large text, and that slider is narrower than Blending and Balance now that one wheel shows.
- [ ] **Step 2: Fix** each item at the shared component or token where it lives, not per screen; skip any that needs the fenced camera files and list it.
- [ ] **Step 3: Run** the whole suite.
- [ ] **Step 4: Re-shoot** every audited screen into `docs/screenshots/e4/` (`e4-clean-<screen>-<v|h>[-ax].png`).
- [ ] **Step 5: Commit** each fix on its own: `fix: <what no longer clips or collides>`.
