# OpenCam Editor Colour Tools, Part E3, Implementation Plan

> **DRAFT written on 2026-11-11, to be checked by Tanner.** It replaces an earlier sliders-only draft with the scope Tanner asked for on 2026-11-11. Everything under "Calls made in this plan" at the end needs his check before this plan is treated as approved.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The editing experience needed to make a look: the Library and the Editor say what each file is (RAW, HEIF, RAW + HEIF, JPEG) and the Editor shows the photo's lens and exposure; a point curve editor (RGB, Red, Green, Blue) over the picture's histogram; colour grading with three wheels; a colour mixer for eight bands. Every new tool is saved in edits and looks and shows wherever a look applies today, the camera's viewfinder and capture included.

**Architecture:** Format and lens facts are read, never stored: the designation comes from the files of a `LibraryItem`, the facts from the original's metadata through ImageIO. The three tools map one colour to another, so they become stages inside `ColourMath.apply` and compile into the same single 33-point Display P3 table as the E1 sliders. Curves are stored as control points (`ToneCurves` inside `Adjustments`); the mixer and grading are new scalar `AdjustmentKey` cases. `LookCompiler`, `LookRenderer`, `LookBaker`, `FramePipeline` and `LookCapture` do not change: they carry `Adjustments` whole, and `ColourCubeCache` keys its table on `Adjustments.colourPart`, which now includes the curves. The histogram is counted off the main actor from each rendered proxy preview. The curve canvas and the wheels are SwiftUI `Canvas` views with gestures; everything around them is system components.

**Tech Stack:** Swift 6, SwiftUI (`Canvas`, `DragGesture`, `SpatialTapGesture`, `Picker`, `Slider`, `.popover`), Core Image (unchanged use), ImageIO (`CGImageSourceCopyPropertiesAtIndex`, Exif keys), Core Graphics, Swift Testing, Xcode 27.2, `xcodebuild`, `simctl`, the interactive iOS Simulator tool.

**Spec:** Tanner's request of 2026-11-11, in his words: "we need to improve the lightroom esc features. Within the library, we should be able to see which photos are raw and which are HEIF, when editing a photo, we should also see this designation here, as well as the lens info. For the lightroom control specifically, I want to be able to see the color curves with the historgram behind it (like in LR), as well as the color wheels. Basicially bring over all the tools as needed to get the full editing experience to make a unique look". Also `docs/superpowers/specs/2026-11-10-opencam-editor-looks-design.md` ("The model", "One renderer", "Calls made without Tanner"). API facts come only from a grep of `$(xcrun --sdk iphoneos --show-sdk-path)` (zsh: quote patterns); the ones this plan uses were checked there on 2026-11-11 and are named in each task.

## Global Constraints

Every constraint of the camera core, E1 and E2 plans applies unchanged:

- "iPhone Duo only, iOS 27.1 or later, Xcode 27.2, Swift 6, SwiftUI." `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, approachable concurrency. File-system-synchronized groups: new files need no project edits. Paths are relative to the repo root.
- "No third-party dependencies." "SwiftUI with system components and system glass throughout; dark appearance only." All four interface orientations. `Theme` for spacing and accent (read, never edited here: see Fence).
- Anti-goals, verbatim: "A look that renders differently in the viewfinder, in the saved file and in the editor. One renderer serves all three." "Sliders that lag behind the finger on a 48 MP photo." "A control for a tool that is not built yet." "An edit that cannot be undone back to the original file." "Imitation blur or glass drawn by hand where a system material exists."
- Code: no force unwraps, force casts or `try!` (tests included); no `Any`-typed values in our APIs (reading an ImageIO dictionary inside one function with `as?`, as `PictureDecoder.pixelSize` does, is the one allowed pattern); one type per file; errors are specific enums, `Error, CustomStringConvertible`, `[Module:Function] Description — {context}`, paths as `url.path(percentEncoded: false)`; no `@preconcurrency import`, `nonisolated(unsafe)` or new `@unchecked Sendable`.
- Copy: plain, factual, sentence case, no em dashes in UI strings, British spelling ("Colour"), nothing named that is not built. Error descriptions are only logged.
- Git: conventional commits, no attribution lines, never force-push.
- Carried from E1 and E2: `LookRenderer.shared` owns the only `CIContext`; every rendered picture is Display P3; `ColourMath` works on Display P3-encoded values with Rec. 709 luma weights; the proxy rule (`EditorModel.proxyLongSide = 2048`); `.edit.json` beside its original, originals never rewritten; an edit file from a newer build is read-only (`EditStoreError.newerVersion`, `LibraryCopy.newerEdit`).

Added by this plan:

- **Worktree and branch:** (pre-flight correction) built in worktree `.claude/worktrees/editor-colour-tools-eb9e9a` on `tannerpham/editor-colour-tools-eb9e9a`, cut from `perf/main-thread-freezes` (68c78af), draft PR tanner-pham/OpenCam#9. `main` holds neither E1 nor E2: every "diff against main" in this plan means `git diff $(git merge-base origin/perf/main-thread-freezes HEAD)`. Camera work continues in another worktree at the same time.
- **Fence (owned paths):** `OpenCam/Edit/`, `OpenCam/Render/ColourMath*.swift`, `OpenCam/Render/ColourCubeCache.swift` (one line, Task 3), `OpenCam/Render/PictureHistogram.swift`, `OpenCam/Render/HistogramChannel.swift`, `OpenCam/Render/ColourTint.swift`, `OpenCam/Library/` (new files, `LookSeeder.swift`, `SampleSeeder.swift`, `LibraryError.swift` for Task 1's `seedFailed` change), `OpenCam/UI/Editor/`, `OpenCam/UI/Library/`, `OpenCamTests/` (new files and the suites named per task; never `Fixture.swift`). The one shared file touched is `OpenCam/App/LaunchConfig.swift`, only in the launch-flag steps of Tasks 1 and 5. Never touched: `OpenCam/App/CameraModel*.swift`, `OpenCam/App/OpenCamApp.swift`, `OpenCam/Capture/`, `OpenCam/Capability/`, the camera screen's files in `OpenCam/UI/` (including `Theme.swift`), `LookRenderer.swift`, `LookCompiler.swift`, `LookBaker.swift`. A need outside the fence is skip-and-flag in the task report, never a silent edit.
- **Simulator:** this worktree uses only `OpenCam Dev B`. Every `scripts/test.sh` and `scripts/shot.sh` command carries `OPENCAM_SIM_NAME="OpenCam Dev B"` in front; the UDID is `UDID=$(OPENCAM_SIM_NAME="OpenCam Dev B" scripts/sim-udid.sh)`. Never `booted`.
- **Test files:** each new test file starts with `import Foundation`, `import Testing` and `@testable import OpenCam`, plus `CoreGraphics`, `CoreImage`, `ImageIO` or `UniformTypeIdentifiers` where it uses them (left out of the code below to save space).
- **Isolation:** every new type in `Edit/`, `Render/` and `Library/` is `nonisolated` and `Sendable`. Only `EditorModel`, `SampleSeeder` and views are main-actor. Histogram counting and fact reading are `@concurrent`.
- **One table rule:** nothing is added to `LookRenderer`'s spatial stage, `renderColourAndVignette` or `FramePipeline`. Exact stage order inside `ColourMath.apply`, written in its doc comment: 1 linear light and exposure, 2 white balance, 3 encoded and contrast, 4 highlights, shadows, whites, blacks (E1, unchanged), **5 point curves (RGB curve, then the channel's own curve)**, 6 vibrance, 7 saturation (E1, unchanged), **8 colour mixer**, **9 colour grading**, 10 clamp. Each new stage is skipped outright when it changes nothing (curves all identity; every mixer value 0; every grading saturation and luminance 0), so every table built before this plan is rebuilt bit for bit (pinned in Task 3).
- **What makes a tool reach the viewfinder and capture:** (a) every scalar key it adds is `isColour`; (b) `Adjustments.isIdentity`, `hasColourChanges`, `matches` and `colourPart` count the curves; (c) `ColourMath.apply` reads it; (d) `Adjustments` encodes and decodes it, because `Look`, `CameraLook`, `SavedSelections` and `PhotoEdit` carry `Adjustments` whole. `LookRenderer.render` skips the table when `hasColourChanges` is false and `LookCapture.finish` skips a look whose `isIdentity` is true, so (b) is load-bearing. Pinned in Task 9.
- **Storage versions:** `PhotoEdit.currentVersion` 1 → 2. `Look` gains `version`, `Look.currentVersion = 2`; a look file without one is version 1. Both stores stamp the current version on every write. `EditFileVersion` keeps its shape. `CameraLook` and `SavedSelections` (camera files) are not versioned.
- **Layout sizes** (outer display 466 x 678 pt with a system strip of about 85 pt, right in portrait and left in landscape; inner display 669 x 951 pt): folded portrait is `.stacked` with a panel about 381 pt wide; folded landscape and the open phone are `.sideBySide` with the 320 pt panel. Stacked, the panel keeps `EditorLayout.minPanelHeight(for:)`: 240 pt, or 340 pt for Curve and Grading. Curve canvas: square, side `min(panel width − 32, panel height − 68)`, where the panel is the space `CurvePanel` gets below the group picker: (pre-flight correction) folded portrait is whatever the stacked 340 pt panel leaves, at least 220 pt, settled by screenshot; 288 pt folded landscape and open. Wheels: diameter `min(160, (panel width − 44) / 2)`: 160 pt folded portrait, 138 pt beside the picture. Three wheels never fit in a row at these widths at 120 pt or more, so they are always a triangle: Midtones on top, Shadows bottom left, Highlights bottom right, Blending and Balance below, in the panel's scroll view.
- **No lag:** every render while a control moves goes through `EditorModel.adjustments` → `RenderCoalescer` → the 2048 px proxy. The histogram has its own coalescer at `.utility` priority and never holds up a render.
- **Exact UI copy, used verbatim:** formats "RAW", "HEIF", "RAW + HEIF", "JPEG", "RAW + JPEG", "PNG"; the info button "Photo info" (also the popover's title); rows "Format", "Lens", "Focal length", "Equivalent focal length", "Aperture", "Shutter", "ISO"; values like "f/1.8", "f/2", "1/120 s", "2 s", "ISO 100", "6.9 mm", "24 mm", joined in the summary by " · ". Groups "Curve", "Mix", "Grading". Curve channels "RGB", "Red", "Green", "Blue"; the picker's label "Curve channel"; the button "Reset"; the canvas's label "<Channel> curve" with value "<n> points". Bands "Red", "Orange", "Yellow", "Green", "Aqua", "Blue", "Purple", "Magenta"; label "Colour band"; sliders "<Band> hue", "<Band> saturation", "<Band> luminance". Wheels "Shadows", "Midtones", "Highlights", each with a readout "<hue>° · <saturation>" ("210° · 35") and a slider shown as "Luminance"; key titles "Shadows hue", "Shadows saturation", "Shadows luminance" (and Midtones, Highlights), "Blending", "Balance". The seeded look "Colour study".
- **Launch flags (Simulator screenshots only):** `-seedFormats on` (Task 1), `-seedStudy on` and `-editorLook <name>` (Task 5); each sets `isScripted`. Seeding runs in `LibraryView.applyLaunch`, never in `OpenCamApp`.
- **Screenshots:** `SHOT_DIR=docs/screenshots/e3`, names prefixed `e3-`, through `scripts/shot.sh` (display 1, the outer display). The implementer reads every PNG.
- **Tap and drag tests:** a control verified only by a screenshot is not verified. For every interactive control, on the folded simulator and then on the open one, with the iOS Simulator tool `control`: one action (`tap`, `swipe` or `touch_path`), wait 2 s, one `xcrun simctl io <UDID> screenshot --display=<n> <scratch>/<step>.png` (the tool's own screenshot can lag a tap), look, write what changed. (Pre-flight correction) Implementers do not run these: after a UI task's review is clean, a separate verifier runs the task's tap-and-drag step. Folded: `OpenCam Dev B` (display 1, 1398 x 2034 px). Open: only the simulator "Claude Duo camera design" (UDID `E4114F51-C78A-4512-B717-7CE404E38BE9`, `--display=3`), shared with the camera session: build into its own derived data (`-derivedDataPath .build-open`), install immediately before each open-display check, keep checks short, and if the screen is not the build just installed, reinstall and retry. No other simulator, never `booted`. A check that cannot be done is reported as Not verified and listed for Tanner, never skipped silently.

## Review Focus

1. Re-saving an edit loaded as version 1 after changing a new tool must write version 2, or the build before this plan would open it as editable and drop the new values on its next save. Pinned by `EditStoreTests.resavingAnOldEditStampsTheCurrentVersion` (Task 2).
2. Edit and look files written before this plan must load with every new tool at its default and build exactly the same table. Pinned by `AdjustmentsTests.e1FileLoadsWithNewToolsAtDefaults` and `ColourMathTests.e1TablesAreRebuiltBitForBit` (Task 3).
3. A look that changes only a curve (a value that is not an `AdjustmentKey`) must still reach the viewfinder's table, the baked HEIF and a RAW capture's edit file. Pinned by `ColourKeyTests.curvesAreInTheTableAndItsCacheKey` (Task 3) and `LookCarryTests.curveMixerAndGradingLooksReachTheViewfinderTheBakeAndTheRAWEdit` (Task 9).
4. A curve must never overshoot its points, a dragged point must never pass a neighbour, and the end points can never be removed. Pinned by `ToneCurveTests.curveNeverOvershootsItsPoints` (Task 3) and `CurveEditingTests.dragsNeverCrossANeighbourAndTheEndsStay` (Task 5).
5. A curve drag must render only the proxy, through the coalescer, and a slow histogram must never delay a preview. Pinned by `EditorHistogramTests.aHeldHistogramNeverDelaysThePreview` (Task 4) and `CurveEditingTests.curveDragRendersTheProxyOnlyThroughTheCoalescer` (Task 5).

---

### Task 1: Format badges and the editor's photo info

**Pre-flight corrections (controller, 2026-11-11; these override the text below):**
- `LibraryError.seedFailed` gains `function: String` (first associated value) and its description reads `"[SampleSeeder:\(function)] Cannot create the sample — {path: …, reason: …}"`; `seedIfEmpty` passes `"seedIfEmpty"`, the new seeder `"seedFormatsIfAbsent"`. `LibraryError.swift` is inside the fence for this.
- The format badge copies the clip badge's style exactly (`.caption`, as `LibraryCell.swift` draws the clip badge), not `.caption2`.
- `EditorModel.load()` starts `PhotoFacts.read` with `async let` at its very top and assigns `facts` once the edit has loaded, on every exit path (ready, read-only, failed), so the read never delays the decode.
- `applyLaunch` order, final after Task 5: seed formats, (Task 5: seed the study look), one `library.reload()`, then choose the launch photo.
- Step 6 is screenshots only (`scripts/shot.sh`). The "Tap-test, folded then open" sentence is run by a separate verifier after review, not by the implementer.

**Files:**
- Create: `OpenCam/Library/FormatDesignation.swift`, `OpenCam/Library/PictureKind.swift`, `OpenCam/Library/PhotoFacts.swift`, `OpenCam/Library/PhotoInfoRow.swift`, `OpenCam/UI/Editor/PhotoInfoLine.swift`
- Modify: `OpenCam/UI/Library/LibraryCell.swift` (badge at bottom leading, the clip badge stays bottom trailing; the accessibility label gains the title: "OC_0004, RAW + HEIF"), `OpenCam/UI/Editor/EditorModel.swift` (`facts`, read at the start of `load()`, before the edit, so a read-only photo still shows them), `OpenCam/UI/Editor/EditorView.swift` (`PhotoInfoLine` under the picture in both layouts; stacked, `pictureHeight` subtracts `PhotoInfoLine.height`), `OpenCam/Library/SampleSeeder.swift`, `OpenCam/UI/Library/LibraryView.swift` (`applyLaunch` seeds formats first, Simulator only, then `library.reload()`), `OpenCam/App/LaunchConfig.swift` (own step)
- Test: `OpenCamTests/FormatDesignationTests.swift`, `OpenCamTests/PhotoFactsTests.swift`; Modify `OpenCamTests/SampleSeederTests.swift`, `OpenCamTests/LaunchConfigTests.swift`

**Interfaces:**
- Consumes: E1 `LibraryItem` (`kind`, `pictureURL`, `rawURL`), `LibraryScanner.group(names:directory:)`, `EditorModel`, `SampleSeeder`, `LibraryView.applyLaunch()`, `LibraryStore.captures`, `CaptureStore(directory:)`, `reserveSequence()`, `url(sequence:kind:)`, `CaptureFileKind`; test helpers `TestFiles.directory()`, `TestFiles.writeOrientedPicture(width:height:orientation:type:metadata:to:)`, `TestFiles.writeJPEG(width:height:rgb:to:)`, `EditorFixture`. ImageIO keys (CGImageProperties.h): `kCGImagePropertyExifDictionary`, `kCGImagePropertyExifLensModel`, `kCGImagePropertyExifFNumber`, `kCGImagePropertyExifExposureTime`, `kCGImagePropertyExifISOSpeedRatings` (an array), `kCGImagePropertyExifFocalLength`, `kCGImagePropertyExifFocalLenIn35mmFilm`.
- Produces:

```swift
nonisolated enum PictureKind: String, Sendable { case heif = "HEIF", jpeg = "JPEG", png = "PNG" }   // from HEIC/HEIF, JPG/JPEG, PNG
nonisolated struct FormatDesignation: Sendable, Equatable {
    let picture: PictureKind?          // nil when the item is a DNG alone
    let hasRAW: Bool; var title: String { get }          // "RAW", "HEIF", "RAW + HEIF", "JPEG", "RAW + JPEG", "PNG"
    static func of(_ item: LibraryItem) -> FormatDesignation?   // nil for a clip
}
nonisolated struct PhotoInfoRow: Sendable, Equatable { let title: String; let value: String }
nonisolated struct PhotoFacts: Sendable, Equatable {
    var lensModel: String?, focalLength: Double?, equivalentFocalLength: Int?, aperture: Double?, exposureTime: Double?, iso: Int?
    static let none = PhotoFacts()
    /// Exif of image 0; a missing file, no Exif, or a value that is absent, not a number or not above 0 leaves that fact nil.
    @concurrent static func read(at url: URL) async -> PhotoFacts
    static func apertureText(_ f: Double) -> String         // 1.8 "f/1.8", 2.0 "f/2"
    static func shutterText(seconds: Double) -> String      // below 1: "1/<round(1/t)> s"; else one decimal, ".0" dropped: "2 s", "2.5 s"
    static func millimetresText(_ mm: Double) -> String     // 6.86 "6.9 mm", 24 "24 mm"
    /// designation, then lens (equivalent focal length, else focal length, else lens model), aperture, shutter, ISO; present ones only.
    func summary(_ designation: FormatDesignation?) -> String
    func rows(_ designation: FormatDesignation?) -> [PhotoInfoRow]   // Format, Lens, Focal length, Equivalent focal length, Aperture, Shutter, ISO
}
// EditorModel: private(set) var facts = PhotoFacts.none; var designation: FormatDesignation? { FormatDesignation.of(item) }
struct PhotoInfoLine: View { let designation: FormatDesignation?; let facts: PhotoFacts; static let height: CGFloat = 36 }
    // A system Button, label: the summary in .footnote, secondary, one line, tail truncated; 44 pt tap target via contentShape. Opens .popover with a List of LabeledContent rows titled "Photo info", .presentationCompactAdaptation(.popover).
// LibraryCell: the designation's title in a capsule like the clip badge (.caption2, .glassEffect(.regular, in: .capsule)).
@MainActor extension SampleSeeder {
    /// 0 when Captures holds any DNG. Else, in order: a scene JPG (no Exif), a placeholder DNG alone, a scene HEIC with the sample Exif, and a scene HEIC with the sample Exif plus a placeholder DNG of the same number (the newest item). The placeholder DNG is the bytes "OpenCam sample placeholder": the Simulator cannot write a real DNG (ImageIO lists no DNG destination type). The sample Exif (private): LensModel "Sample lens 6.9mm f/1.8", FocalLength 6.9, FocalLenIn35mmFilm 24, FNumber 1.8, ExposureTime 1/120, ISOSpeedRatings [100], written with CGImageDestination (HEIC encoding already works in this Simulator's tests).
    static func seedFormatsIfAbsent(_ captures: CaptureStore) throws(LibraryError) -> Int    // 4
}
// LaunchConfig.seedsFormats: Bool   (-seedFormats on, Simulator only, sets isScripted)
```

- [ ] **Step 1: Write the failing tests**

```swift
// OpenCamTests/FormatDesignationTests.swift
@Suite struct FormatDesignationTests {
    @Test func designationsFollowTheFiles() {
        let names = ["OC_0001.DNG", "OC_0001.HEIC", "OC_0002.HEIC", "OC_0003.DNG", "OC_0004.JPG", "OC_0005.jpeg", "OC_0006.PNG",
                     "OC_0007.HEIF", "OC_0008.JPG", "OC_0008.DNG", "OC_0009.MOV"]
        let items = LibraryScanner.group(names: names, directory: URL(filePath: "/tmp/c"))
        let titles = Dictionary(uniqueKeysWithValues: items.map { ($0.id, FormatDesignation.of($0)?.title ?? "clip") })
        #expect(titles == ["OC_0001": "RAW + HEIF", "OC_0002": "HEIF", "OC_0003": "RAW", "OC_0004": "JPEG", "OC_0005": "JPEG",
                           "OC_0006": "PNG", "OC_0007": "HEIF", "OC_0008": "RAW + JPEG", "OC_0009.MOV": "clip"]) } }
// OpenCamTests/PhotoFactsTests.swift
@Suite struct PhotoFactsTests {
    let exif: [CFString: Any] = [kCGImagePropertyExifLensModel: "Sample lens 6.9mm f/1.8", kCGImagePropertyExifFNumber: 1.8,
                                 kCGImagePropertyExifExposureTime: 1.0 / 120, kCGImagePropertyExifISOSpeedRatings: [100],
                                 kCGImagePropertyExifFocalLength: 6.86, kCGImagePropertyExifFocalLenIn35mmFilm: 24]
    @Test func readsLensAndExposureFromExif() async throws {
        for type in [UTType.heic, .jpeg] {
            let url = try TestFiles.writeOrientedPicture(width: 32, height: 24, orientation: 1, type: type,
                                                         metadata: [kCGImagePropertyExifDictionary: exif], to: TestFiles.directory().appending(path: "OC_0001.\(type == .heic ? "HEIC" : "JPG")"))
            let facts = await PhotoFacts.read(at: url); #expect(facts.lensModel == "Sample lens 6.9mm f/1.8"); #expect(facts.equivalentFocalLength == 24); #expect(facts.iso == 100)
            #expect(facts.summary(FormatDesignation(picture: .heif, hasRAW: true)) == "RAW + HEIF · 24 mm · f/1.8 · 1/120 s · ISO 100")
            #expect(facts.rows(nil).map(\.title) == ["Lens", "Focal length", "Equivalent focal length", "Aperture", "Shutter", "ISO"]); #expect(facts.rows(nil)[1].value == "6.9 mm") } }
    @Test func factsTheFileDoesNotCarryAreLeftOut() async throws {
        let dir = try TestFiles.directory(); let plain = try TestFiles.writeJPEG(width: 16, height: 16, rgb: SIMD3(0.5, 0.5, 0.5), to: dir.appending(path: "OC_0002.JPG"))
        #expect(await PhotoFacts.read(at: plain) == .none); #expect(PhotoFacts.none.summary(FormatDesignation(picture: .jpeg, hasRAW: false)) == "JPEG")
        #expect(PhotoFacts.none.rows(FormatDesignation(picture: .jpeg, hasRAW: false)) == [PhotoInfoRow(title: "Format", value: "JPEG")])
        #expect(await PhotoFacts.read(at: dir.appending(path: "missing.HEIC")) == .none); let partial = try TestFiles.writeOrientedPicture(width: 16, height: 16, orientation: 1, type: .jpeg,
            metadata: [kCGImagePropertyExifDictionary: [kCGImagePropertyExifFNumber: 0, kCGImagePropertyExifFocalLength: 4.2]], to: dir.appending(path: "OC_0003.JPG"))
        #expect(await PhotoFacts.read(at: partial).summary(nil) == "4.2 mm")          // f/0 is not a fact
    }
    @Test func formatsShutterApertureAndFocal() {
        #expect(PhotoFacts.shutterText(seconds: 1.0 / 120) == "1/120 s"); #expect(PhotoFacts.shutterText(seconds: 0.5) == "1/2 s")
        #expect(PhotoFacts.shutterText(seconds: 2) == "2 s"); #expect(PhotoFacts.shutterText(seconds: 2.5) == "2.5 s")
        #expect(PhotoFacts.apertureText(1.78) == "f/1.8"); #expect(PhotoFacts.apertureText(2) == "f/2")
        #expect(PhotoFacts.millimetresText(6.86) == "6.9 mm"); #expect(PhotoFacts.millimetresText(24) == "24 mm") }
    @MainActor @Test func editorReadsTheFactsOfItsPhoto() async throws {
        let (model, _, _) = try await EditorFixture.make(width: 64, height: 48); #expect(model.designation?.title == "JPEG"); #expect(model.facts == .none) } }
// Added to SampleSeederTests
@Test func formatSamplesMakeEachDesignationOnce() throws {
    let dir = try TestFiles.directory(); let captures = try CaptureStore(directory: dir)
    #expect(try SampleSeeder.seedFormatsIfAbsent(captures) == 4); #expect(try SampleSeeder.seedFormatsIfAbsent(captures) == 0)
    #expect(LibraryScanner.items(in: dir).compactMap { FormatDesignation.of($0)?.title } == ["RAW + HEIF", "HEIF", "RAW", "JPEG"]) }
// Added to LaunchConfigTests
@Test func parsesSeedFormatsFlag() {
    #expect(LaunchConfig.parse(["app", "-seedFormats", "on"]).seedsFormats); #expect(LaunchConfig.parse(["app", "-seedFormats", "on"]).isScripted)
    #expect(!LaunchConfig.parse(["app"]).seedsFormats) }
```

- [ ] **Step 2: Run to see them fail.** `OPENCAM_SIM_NAME="OpenCam Dev B" scripts/test.sh FormatDesignationTests`. Expected: build error `cannot find 'FormatDesignation' in scope`.
- [ ] **Step 3: Implement the model types and the editor wiring.** `PhotoFacts.read` uses `CGImageSourceCreateWithURL` and `CGImageSourceCopyPropertiesAtIndex(source, 0, nil)`, reading the Exif dictionary as `[CFString: Any]` inside the function only; numbers come through `as? Double` / `as? Int`, ISO through `as? [Int]` and its first element.
- [ ] **Step 4: The launch flag (the only shared file in this task).** `OpenCam/App/LaunchConfig.swift`: `var seedsFormats = false  // -seedFormats on (honoured in the Simulator only)`; parsed like `-seedLook`; the `isScripted` doc comment lists it. `LibraryView.applyLaunch` calls `SampleSeeder.seedFormatsIfAbsent(library.captures)` under `#if targetEnvironment(simulator)` when it is set, logs a `LibraryError`, then `library.reload()`, before choosing the launch photo.
- [ ] **Step 5: Run to see them pass.** `OPENCAM_SIM_NAME="OpenCam Dev B" scripts/test.sh FormatDesignationTests && OPENCAM_SIM_NAME="OpenCam Dev B" scripts/test.sh PhotoFactsTests && OPENCAM_SIM_NAME="OpenCam Dev B" scripts/test.sh SampleSeederTests && OPENCAM_SIM_NAME="OpenCam Dev B" scripts/test.sh LaunchConfigTests && OPENCAM_SIM_NAME="OpenCam Dev B" scripts/test.sh EditorModelTests`. Expected: `** TEST SUCCEEDED **` five times.
- [ ] **Step 6: Screenshots and taps**

```bash
export SHOT_DIR=docs/screenshots/e3
OPENCAM_SIM_NAME="OpenCam Dev B" SHOT_FRESH=1 scripts/shot.sh e3-library-formats-v -orientation portrait -screen library -seedSamples on -seedFormats on
OPENCAM_SIM_NAME="OpenCam Dev B" scripts/shot.sh e3-library-formats-h -orientation landscape -screen library -seedSamples on -seedFormats on
OPENCAM_SIM_NAME="OpenCam Dev B" scripts/shot.sh e3-editor-info-v -orientation portrait -screen editor -seedSamples on -seedFormats on
OPENCAM_SIM_NAME="OpenCam Dev B" scripts/shot.sh e3-editor-info-h -orientation landscape -screen editor -seedSamples on -seedFormats on
```

Pass when: every photo tile has its badge (RAW + HEIF, HEIF, RAW, JPEG x4) at bottom left, legible, not clipped, clips unchanged; the RAW-only tile shows "This photo could not be opened." with its RAW badge (placeholder DNG); the editor shows "RAW + HEIF · 24 mm · f/1.8 · 1/120 s · ISO 100" under the picture, whole in landscape and tail-truncated in portrait only if it must be. Tap-test, folded then open: tap the info line, the "Photo info" popover lists Format, Lens "Sample lens 6.9mm f/1.8", Focal length "6.9 mm", Equivalent focal length "24 mm", Aperture, Shutter, ISO; tap outside, it closes; tap the JPEG scene tile, its line says "JPEG" alone.
- [ ] **Step 7: Commit** `git add OpenCam OpenCamTests docs/screenshots/e3 && git commit -m "feat: show each photo's format in the library and its lens and exposure in the editor"`

---

### Task 2: File versions for edits and looks

**Pre-flight corrections (controller, 2026-11-11; these override the text below):**
- Step 2's expected failure is a build error (`Look` has no `version`, `LookStoreError` has no `newerVersion`), not a failing `PhotoEdit.currentVersion == 2`.

The draft's Task 2, unchanged in design.

**Files:**
- Modify: `OpenCam/Edit/PhotoEdit.swift` (`currentVersion = 2`), `OpenCam/Edit/EditStore.swift` (`save` writes a copy whose `version` is `PhotoEdit.currentVersion`, whatever it was loaded with; refusal of newer files unchanged), `OpenCam/Edit/EditFileVersion.swift` (doc comment: "an edit or look file"), `OpenCam/Edit/Look.swift`, `OpenCam/Edit/LookStore.swift` (`write` stamps `Look.currentVersion`; `rename` and `duplicate` throw `.newerVersion` for a stored version above it and leave the file; `all()` still lists such looks and `delete` removes them; a look file that does not decode reports `.newerVersion` when `EditFileVersion` reads a version above the current one, else `.unreadable`), `OpenCam/Edit/LookStoreError.swift`
- Test: Modify `OpenCamTests/EditStoreTests.swift`, `OpenCamTests/LookStoreTests.swift`

**Interfaces:**
- Consumes: E1 `PhotoEdit`, `EditStore`, `EditFileVersion`, `Look`, `LookStore`, `LookStoreError`; `TestFiles.directory()`; `LooksPanel`'s failure path, which already catches every `LookStoreError`.
- Produces:

```swift
// PhotoEdit.currentVersion == 2
nonisolated struct Look: Codable, Sendable, Equatable, Identifiable {
    static let currentVersion = 2
    let id: UUID; var name: String; var adjustments: Adjustments; let createdAt: Date; var version = Look.currentVersion
    init(id: UUID, name: String, adjustments: Adjustments, createdAt: Date)   // existing callers unchanged
    init(from decoder: any Decoder) throws                                    // a missing version is 1; unknown keys ignored
}
// LookStoreError gains:
case newerVersion(path: String, version: Int)
    // "[LookStore:write] Look file was written by a newer version and is read-only here — {path: P, version: V, supported: 2}"
```

Why this makes the build before this plan read-only: that build has `PhotoEdit.currentVersion == 1`, its `EditStore.refuseUnwritable` throws `.newerVersion` above 1, its `EditorModel.load` opens such an edit as `LibraryCopy.newerEdit`, and its `LookChange` skips it. Look files: that build reads no version from a look, so it lists a newer look without the new tools and a rename there drops them. From this build on, look files carry the rule.

- [ ] **Step 1: Write the failing tests**

```swift
// Added to EditStoreTests
@Test func resavingAnOldEditStampsTheCurrentVersion() throws {   // Review Focus 1
    let dir = try TestFiles.directory(), store = EditStore(directory: dir); #expect(PhotoEdit.currentVersion == 2)
    for (stem, json) in [("OC_0006", #"{"version": 1, "adjustments": {"exposure": 1}}"#), ("OC_0007", #"{"adjustments": {"exposure": 1}}"#)] {
        let url = dir.appending(path: "\(stem).edit.json"); try Data(json.utf8).write(to: url); var edit = try store.load(stem: stem)
        #expect(edit.version == 1); #expect(edit.adjustments == Adjustments().setting(.exposure, to: 1))
        edit.adjustments.exposure = 2; try store.save(edit, stem: stem); #expect(try JSONDecoder().decode(EditFileVersion.self, from: Data(contentsOf: url)).version == 2); #expect(try store.load(stem: stem).version == 2) } }
// Added to LookStoreTests
func writeLook(_ json: String, in store: LookStore, id: UUID) throws -> URL {
    let url = store.directory.appending(path: "\(id.uuidString).json"); try Data(json.utf8).write(to: url); return url }
@Test func lookFilesFromBeforeLoadAsVersionOneAndAreStampedOnWrite() throws {
    let store = try LookStore(directory: TestFiles.directory()), id = UUID()
    let url = try writeLook(#"{"id": "\#(id.uuidString)", "name": "Old", "adjustments": {"temperature": 20}, "createdAt": "2026-11-10T09:00:00Z"}"#, in: store, id: id)
    #expect(store.all().map(\.version) == [1]); #expect(store.all().first?.adjustments == Adjustments().setting(.temperature, to: 20)); _ = try store.rename(id, to: "Older")
    #expect(try JSONDecoder().decode(EditFileVersion.self, from: Data(contentsOf: url)).version == 2); #expect(try store.save(name: "New", adjustments: Adjustments()).version == 2) }
@Test func newerLookIsListedButNotRenamedOrDuplicated() throws {
    let store = try LookStore(directory: TestFiles.directory()), id = UUID()
    let json = #"{"id": "\#(id.uuidString)", "name": "Future", "version": 3, "adjustments": {"exposure": 1, "masks": []}, "createdAt": "2026-11-10T09:00:00Z"}"#
    let url = try writeLook(json, in: store, id: id), path = url.path(percentEncoded: false)
    #expect(store.all().map(\.name) == ["Future"]); #expect(throws: LookStoreError.newerVersion(path: path, version: 3)) { try store.rename(id, to: "Now") }
    #expect(throws: LookStoreError.newerVersion(path: path, version: 3)) { try store.duplicate(id) }
    #expect(try Data(contentsOf: url) == Data(json.utf8)); try store.delete(id); #expect(store.all().isEmpty) }
```

- [ ] **Step 2: Run to see them fail.** `OPENCAM_SIM_NAME="OpenCam Dev B" scripts/test.sh EditStoreTests`. Expected: fails on `PhotoEdit.currentVersion == 2`.
- [ ] **Step 3: Implement.** Existing tests that use versions 3, 7 and 99 still mean "newer" and stay unchanged.
- [ ] **Step 4: Run to see them pass.** `OPENCAM_SIM_NAME="OpenCam Dev B" scripts/test.sh` with each of `EditStoreTests`, `LookStoreTests`, `EditorModelTests`, `LibraryLookTests`, `UnreadableEditTests`, `LookCaptureTests`, `CameraLookTests`. Expected: `** TEST SUCCEEDED **` seven times.
- [ ] **Step 5: Commit** `git add OpenCam OpenCamTests && git commit -m "feat: version edit files 2 and give look files a version"`

---

### Task 3: Point curves in the colour table

**Pre-flight corrections (controller, 2026-11-11; these override the text below):**
- Order (Step 3's reference check cannot compile after Step 2): do Step 1, add `e1TablesAreRebuiltBitForBit` alone to `ColourMathTests`, run `ColourMathTests` green against today's `ColourMath`, then write the rest of Step 2's tests and see them fail.
- `E1ColourReference` copies `apply` and every helper it calls unqualified (`decode`, `encode`, `luma`, both `clamp01`) verbatim as private statics, so it compiles and never changes again.
- Stage comments: add a stage-list doc comment on `ColourMath.apply`, renumber the existing inline stage comments to this plan's scheme, rename the E1 "tone curves" stage to "tones (highlights, shadows, whites, blacks)" so it does not clash with point curves, and update the stage comment in `ColourMathTests.swift` that uses the old numbers. List only the stages that exist after this task (clamp last); Tasks 7 and 8 insert theirs and renumber clamp.
- `ToneCurve` normalisation: the `minGap` comparison is on integer thousandths (`Int((x * 1000).rounded())`, a gap below 10 is too close), never a `Double` subtraction (0.21 − 0.20 < 0.01 in `Double`). The first and the last sorted points are never dropped: an inner point within `minGap` of the last point is dropped instead; first and last closer than `minGap` give `identity`.
- `Adjustments`' custom `encode(to:)` writes exactly the 14 keys the synthesized encoder wrote today (same names) plus `"curves"` only when not identity, so `ThumbnailCache`'s sorted-keys hash of every existing edit is unchanged.

**Files:**
- Create: `OpenCam/Edit/CurvePoint.swift`, `OpenCam/Edit/CurveChannel.swift`, `OpenCam/Edit/ToneCurve.swift`, `OpenCam/Edit/ToneCurves.swift`, `OpenCamTests/E1ColourReference.swift`
- Modify: `OpenCam/Edit/Adjustments.swift`, `OpenCam/Render/ColourMath.swift` (stage 5 and the doc comment), `OpenCam/Render/ColourCubeCache.swift` (`colourPart(of:)` is replaced by `adjustments.colourPart`; nothing else)
- Test: `OpenCamTests/ToneCurveTests.swift`; Modify `OpenCamTests/AdjustmentsTests.swift`, `OpenCamTests/ColourMathTests.swift`, `OpenCamTests/ColourKeyTests.swift`, `OpenCamTests/LookSelectionTests.swift`

**Interfaces:**
- Consumes: E1 `Adjustments`, `AdjustmentKey`, `ColourMath.apply(_:to:)`, `LookCompiler.cube(for:)`, `ColourCubeCache(build:)`, `LookSelection`, `LookSeeder.warmFade`; test helper `CallCounter` (`increment()`, `value`).
- Produces:

```swift
nonisolated struct CurvePoint: Codable, Sendable, Hashable { var x: Double; var y: Double }   // both 0...1
nonisolated enum CurveChannel: String, CaseIterable, Sendable { case master, red, green, blue
    var title: String { get } }                                     // "RGB", "Red", "Green", "Blue"
nonisolated struct ToneCurve: Codable, Sendable, Hashable {
    static let maxPoints = 16, minGap = 0.01
    static let identity: ToneCurve                                  // [(0, 0), (1, 1)]
    private(set) var points: [CurvePoint]
    /// Normalises: each coordinate clamped to 0...1 and snapped as `(v * 1000).rounded() / 1000`; sorted by x; a point closer than `minGap` in x to the one kept before it is dropped; above `maxPoints` the first 15 and the last are kept; fewer than 2 left is `identity`.
    init(points: [CurvePoint])
    init(from decoder: any Decoder) throws                          // {"points": [{"x":…,"y":…}, …]} through init(points:)
    var isIdentity: Bool { get }                                    // points == identity.points
    /// Flat outside the end points; monotone cubic Hermite between them (formula below); result clamped to 0...1.
    func value(at x: Float) -> Float }
nonisolated struct ToneCurves: Codable, Sendable, Hashable {
    var master = ToneCurve.identity, red = ToneCurve.identity, green = ToneCurve.identity, blue = ToneCurve.identity
    subscript(channel: CurveChannel) -> ToneCurve { get set }
    var isIdentity: Bool { get }
    // Coding: keys "master", "red", "green", "blue"; only non-identity channels are written; a missing channel is identity.
}
// Adjustments gains `var curves = ToneCurves()`. isIdentity: today's rule && curves.isIdentity. hasColourChanges: today's rule || !curves.isIdentity.
// matches: today's snapped rule && curves == other.curves (exact: ToneCurve stores snapped values). var colourPart: Adjustments (non-colour keys zeroed, curves kept).
// Decoding: "curves" optional; a malformed value throws (the edit is then unreadable, read-only, never overwritten). Encoding: a custom encode(to:) writes every scalar key as today, plus "curves" only when not identity.
// ColourMath.apply, stage 5 (skipped when adjustments.curves.isIdentity): per channel c, x_c = curves[c].value(at: curves.master.value(at: x_c)).
```

The curve formula, exact (write it in `ToneCurve`'s doc comment). Points `(x_k, y_k)`, `k = 0…n`. Spacing `h_k = x_{k+1} − x_k`, secants `d_k = (y_{k+1} − y_k)/h_k`. Tangents (Fritsch–Butland, monotone for any spacing): `m_0 = d_0`, `m_n = d_{n−1}`; inside, `m_k = 0` when `d_{k−1}·d_k ≤ 0`, else `m_k = (w_1 + w_2)/(w_1/d_{k−1} + w_2/d_k)` with `w_1 = 2h_k + h_{k−1}`, `w_2 = h_k + 2h_{k−1}`. On the segment holding `x`, `t = (x − x_k)/h_k`: `y = (2t³−3t²+1)·y_k + (t³−2t²+t)·h_k·m_k + (−2t³+3t²)·y_{k+1} + (t³−t²)·h_k·m_{k+1}`. Tangents are computed for the one segment being evaluated (two of them, from three secants), so `apply` needs no precomputation and `LookCompiler` does not change.

- [ ] **Step 1: Freeze today's colour maths.** Copy the body of today's `ColourMath.apply` and its two `clamp01` helpers verbatim into `OpenCamTests/E1ColourReference.swift` as `enum E1ColourReference { static func apply(_ a: Adjustments, to rgb: SIMD3<Float>) -> SIMD3<Float> }` (reading `a[key]` for each E1 key). This file never changes again.
- [ ] **Step 2: Write the failing tests**

```swift
// OpenCamTests/ToneCurveTests.swift
@Suite struct ToneCurveTests {
    func curve(_ p: [(Double, Double)]) -> ToneCurve { ToneCurve(points: p.map { CurvePoint(x: $0.0, y: $0.1) }) }
    @Test func identityAndThroughItsPoints() {
        for i in 0...100 { let x = Float(i) / 100; #expect(abs(ToneCurve.identity.value(at: x) - x) < 1e-6) }
        let lift = curve([(0, 0), (0.5, 0.6), (1, 1)]); #expect(abs(lift.value(at: 0.5) - 0.6) < 1e-6); #expect(abs(lift.value(at: 0.25) - 0.315) < 1e-5)   // m0 1.2, m1 0.96
        let ends = curve([(0.1, 0.2), (0.9, 0.8)]); #expect(ends.value(at: 0) == 0.2); #expect(ends.value(at: 1) == 0.8); #expect(abs(ends.value(at: 0.5) - 0.5) < 1e-6)
        #expect(abs(curve([(0, 0), (0.4, 0.8), (0.6, 0.8), (1, 1)]).value(at: 0.5) - 0.8) < 1e-6)            // a plateau stays flat
    }
    @Test func curveNeverOvershootsItsPoints() {   // Review Focus 4
        var seed: UInt64 = 42
        func next() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 11) / Double(1 << 53) }
        for _ in 0..<200 {
            let c = curve([(0, next())] + (0..<Int(next() * 6)).map { _ in (0.05 + 0.9 * next(), next()) } + [(1, next())]); let p = c.points
            for k in 0..<(p.count - 1) {
                let lo = Float(min(p[k].y, p[k + 1].y)), hi = Float(max(p[k].y, p[k + 1].y))
                for s in 0...50 {
                    let y = c.value(at: Float(p[k].x + (p[k + 1].x - p[k].x) * Double(s) / 50)); #expect(y >= lo - 1e-5 && y <= hi + 1e-5, "\(p) segment \(k)") } } }
        let rising = curve([(0, 0.1), (0.2, 0.15), (0.3, 0.6), (0.7, 0.62), (1, 0.9)]); var last: Float = 0
        for i in 0...1000 { let y = rising.value(at: Float(i) / 1000); #expect(y >= last - 1e-6); last = y } }
    @Test func normalisesWhatItIsGiven() throws {
        #expect(ToneCurve.identity.points == [CurvePoint(x: 0, y: 0), CurvePoint(x: 1, y: 1)])
        #expect(curve([(1.2, 1), (0.12345, 0.5), (-0.1, 0), (0.125, 0.9)]).points == [CurvePoint(x: 0, y: 0), CurvePoint(x: 0.123, y: 0.5), CurvePoint(x: 1, y: 1)])
        #expect(curve([(0.5, 0.5)]) == .identity); let many = curve((0...19).map { (Double($0) / 19, Double($0) / 19) })
        #expect(many.points.count == 16); #expect(many.points.last == CurvePoint(x: 1, y: 1))
        let json = Data(#"{"master": {"points": [{"x": 0, "y": 0.1}, {"x": 1, "y": 1}]}, "luminance": {}}"#.utf8); let decoded = try JSONDecoder().decode(ToneCurves.self, from: json)
        #expect(decoded.master == curve([(0, 0.1), (1, 1)])); #expect(decoded.red.isIdentity); #expect(!decoded.isIdentity) } }
// Added to AdjustmentsTests
@Test func e1FileLoadsWithNewToolsAtDefaults() throws {   // Review Focus 2
    let a = try JSONDecoder().decode(Adjustments.self, from: Data(#"{"exposure": 1, "saturation": 20, "toneCurve": [0, 1]}"#.utf8))
    #expect(a == Adjustments().setting(.exposure, to: 1).setting(.saturation, to: 20)); #expect(a.curves.isIdentity)
    #expect(!String(decoding: try JSONEncoder().encode(a), as: UTF8.self).contains("curves")) }
@Test func curvesCountForIdentityMatchingAndRoundTrip() throws {
    var a = Adjustments(); a.curves.blue = ToneCurve(points: [CurvePoint(x: 0, y: 0.05), CurvePoint(x: 1, y: 1)])
    #expect(!a.isIdentity); #expect(a.hasColourChanges); #expect(!a.matches(Adjustments())); #expect(try JSONDecoder().decode(Adjustments.self, from: JSONEncoder().encode(a)) == a)
    var b = a; b.curves.blue = .identity; #expect(b == Adjustments()); #expect(a.setting(.grain, to: 40).colourPart == a); #expect(a.colourPart.curves == a.curves) }
// Added to ColourMathTests
@Test func e1TablesAreRebuiltBitForBit() {   // Review Focus 2
    for a in [Adjustments(), LookSeeder.warmFade, Adjustments().setting(.contrast, to: 60).setting(.tint, to: -30)] {
        var expected = [Float]()   // LookCompiler's order: red fastest, then green, then blue; alpha 1
        for b in 0..<33 { for g in 0..<33 { for r in 0..<33 {
            let out = E1ColourReference.apply(a, to: SIMD3(Float(r) / 32, Float(g) / 32, Float(b) / 32)); expected += [out.x, out.y, out.z, 1]
        } } }
        #expect(LookCompiler.cube(for: a).data == expected) } }
@Test func masterRunsBeforeTheChannelCurve() {
    var a = Adjustments(); a.curves.master = ToneCurve(points: [CurvePoint(x: 0, y: 0), CurvePoint(x: 0.5, y: 0.6), CurvePoint(x: 1, y: 1)])
    #expect(maxDiff(ColourMath.apply(a, to: grey), SIMD3(0.6, 0.6, 0.6)) < 1e-4); a.curves.red = ToneCurve(points: [CurvePoint(x: 0, y: 0), CurvePoint(x: 0.5, y: 0.7), CurvePoint(x: 1, y: 1)])
    #expect(maxDiff(ColourMath.apply(a, to: grey), SIMD3(0.77536, 0.6, 0.6)) < 1e-4) }   // red curve at 0.6
// Added to ColourKeyTests
@Test func curvesAreInTheTableAndItsCacheKey() {   // Review Focus 3
    var curved = Adjustments(); curved.curves.master = ToneCurve(points: [CurvePoint(x: 0, y: 0.1), CurvePoint(x: 1, y: 1)])
    let builds = CallCounter(), cache = ColourCubeCache { builds.increment(); return LookCompiler.cube(for: $0) }; _ = cache.cube(for: Adjustments()); let table = cache.cube(for: curved)
    #expect(builds.value == 2); #expect(table == LookCompiler.cube(for: curved)); #expect(table != LookCompiler.cube(for: Adjustments()))
    _ = cache.cube(for: curved.setting(.vignette, to: -30)); #expect(builds.value == 2) }
// Added to LookSelectionTests
@Test func looksDifferingOnlyInACurveAreToldApart() {
    var c1 = Adjustments(), c2 = Adjustments()
    c1.curves.master = ToneCurve(points: [CurvePoint(x: 0, y: 0.1), CurvePoint(x: 1, y: 1)]); c2.curves.master = ToneCurve(points: [CurvePoint(x: 0, y: 0.12), CurvePoint(x: 1, y: 1)])
    let a = Look(id: UUID(), name: "A", adjustments: c1, createdAt: .now), b = Look(id: UUID(), name: "B", adjustments: c2, createdAt: .now)
    #expect(LookSelection.selectedLook(among: [a, b], for: c2, lookName: nil)?.id == b.id) }
```

- [ ] **Step 3: Run to see them fail.** `OPENCAM_SIM_NAME="OpenCam Dev B" scripts/test.sh ToneCurveTests`. Expected: build error `cannot find 'ToneCurve' in scope`. Before changing `ColourMath`, `OPENCAM_SIM_NAME="OpenCam Dev B" scripts/test.sh ColourMathTests` with `e1TablesAreRebuiltBitForBit` alone added must pass; if it does not, the reference copy is wrong.
- [ ] **Step 4: Implement the Interfaces.** `ColourCubeCache.cube(for:)` keys on `adjustments.colourPart`; its private `colourPart(of:)` is deleted.
- [ ] **Step 5: Run to see them pass.** `OPENCAM_SIM_NAME="OpenCam Dev B" scripts/test.sh` with each of `ToneCurveTests`, `AdjustmentsTests`, `ColourMathTests`, `ColourKeyTests`, `LookSelectionTests`, `LookCompilerTests`, `LookRendererTests`, `EditStoreTests`. Expected: `** TEST SUCCEEDED **` eight times.
- [ ] **Step 6: Commit** `git add OpenCam OpenCamTests && git commit -m "feat: store point curves and compile them into the colour table"`

---

### Task 4: Histogram of the rendered picture

**Pre-flight corrections (controller, 2026-11-11; these override the text below):**
- `OpenCam/Render/HistogramChannel.swift` is inside the fence.

**Files:**
- Create: `OpenCam/Render/PictureHistogram.swift`, `OpenCam/Render/HistogramChannel.swift`
- Modify: `OpenCam/UI/Editor/EditorModel.swift`
- Test: `OpenCamTests/EditorHistogramTests.swift`

**Interfaces:**
- Consumes: E1 `EditorModel` (`show(_:adjustments:generation:)`, `waitForPreview()`, `previewRenderCount`, `renderPreview` seam), `RenderCoalescer<Value>` (`request`, `finish`, `isIdle`), `PictureDecoder`, `TestFiles`, `EditorFixture`.
- Produces:

```swift
nonisolated enum HistogramChannel: CaseIterable, Sendable { case luma, red, green, blue }
nonisolated struct PictureHistogram: Sendable, Equatable {
    static let binCount = 256, sampleLongSide = 256
    let luma: [UInt32], red: [UInt32], green: [UInt32], blue: [UInt32]   // 256 bins each
    /// Counts RGBA8 bytes (alpha ignored). Luma bin: Int((0.2126·r + 0.7152·g + 0.0722·b).rounded()), on the encoded bytes.
    static func counting(rgba: [UInt8]) -> PictureHistogram
    /// Draws `image` into an RGBA8 Display P3 bitmap whose long side is at most `sampleLongSide`, then counts it. Nil when the bitmap cannot be made. The preview is already Display P3 and encoded, so the bins are the values the curve's x axis shows.
    @concurrent static func make(from image: CGImage) async -> PictureHistogram?
    /// count / peak, capped at 1; peak is the largest count over bins 1...254 of all four channels (at least 1), so a clipped spike at 0 or 255 does not flatten the rest.
    func heights(_ channel: HistogramChannel) -> [Double] }
// EditorModel: private(set) var histogram: PictureHistogram?; func waitForHistogram() async. init gains, after renderPreview, the test seam
//   makeHistogram: (@Sendable (CGImage) async -> PictureHistogram?)? = nil. show(...) requests a histogram of the new preview through its own RenderCoalescer<CGImage>, in a Task(priority: .utility); a result is kept only if its preview is still the newest one counted; the preview path never awaits it.
```

- [ ] **Step 1: Write the failing tests**

```swift
// OpenCamTests/EditorHistogramTests.swift
actor HistogramGate {   // holds every histogram until opened
    private var isOpen = false, waiting: [CheckedContinuation<Void, Never>] = []
    func pass() async { if !isOpen { await withCheckedContinuation { waiting.append($0) } } }
    func open() { isOpen = true; waiting.forEach { $0.resume() }; waiting = [] } }
@MainActor @Suite struct EditorHistogramTests {
    @Test func countsChannelsAndLuma() {
        let h = PictureHistogram.counting(rgba: [255, 0, 0, 255, 0, 0, 0, 255, 128, 128, 128, 0])
        #expect(h.red[255] == 1); #expect(h.red[0] == 1); #expect(h.red[128] == 1); #expect(h.green[0] == 2)
        #expect(h.luma[54] == 1); #expect(h.luma[0] == 1); #expect(h.luma[128] == 1); #expect(h.luma.reduce(0, +) == 3)
        #expect(h.heights(.red)[255] == 1); #expect(h.heights(.red)[128] == 1)          // the peak ignores bins 0 and 255
    }
    @Test func histogramOfAGreyProxyPeaksAtItsGrey() async throws {
        let (model, _, _) = try await EditorFixture.make(width: 640, height: 480); await model.waitForHistogram(); let h = try #require(model.histogram)
        #expect(h.luma.reduce(0, +) == 256 * 192); #expect((126...130).contains(h.luma.firstIndex { $0 > 0 } ?? 0)) }
    @Test func aHeldHistogramNeverDelaysThePreview() async throws {   // Review Focus 5
        let captures = try TestFiles.directory(), gate = HistogramGate()
        _ = try TestFiles.writeJPEG(width: 640, height: 480, rgb: SIMD3(0.5, 0.5, 0.5), to: captures.appending(path: "OC_0001.JPG"))
        guard let item = LibraryScanner.items(in: captures).first else { throw TestFileError.bitmapUnavailable }
        let model = EditorModel(item: item, edits: EditStore(directory: captures), looks: try LookStore(directory: TestFiles.directory()),
                                makeHistogram: { image in await gate.pass(); return await PictureHistogram.make(from: image) })
        await model.load(); #expect(model.phase == .ready); #expect(model.histogram == nil)
        for v in stride(from: 10.0, through: 60, by: 10) { model.adjustments[.contrast] = v; await model.waitForPreview() }
        #expect(model.renderedAdjustments?[.contrast] == 60); #expect(model.previewRenderCount == 7); #expect(model.histogram == nil); await gate.open(); await model.waitForHistogram()
        #expect(model.histogram != nil) } }
```

- [ ] **Step 2: Run to see them fail.** `OPENCAM_SIM_NAME="OpenCam Dev B" scripts/test.sh EditorHistogramTests`. Expected: build error `cannot find 'PictureHistogram' in scope`.
- [ ] **Step 3: Implement.** `make(from:)` uses a `CGContext` (8 bits, `noneSkipLast`, `CGColorSpace.displayP3`) with its own `[UInt8]` buffer, `.medium` interpolation. `waitForHistogram()` loops like `waitForPreview()` over the histogram coalescer and task.
- [ ] **Step 4: Run to see them pass.** `OPENCAM_SIM_NAME="OpenCam Dev B" scripts/test.sh EditorHistogramTests && OPENCAM_SIM_NAME="OpenCam Dev B" scripts/test.sh EditorModelTests && OPENCAM_SIM_NAME="OpenCam Dev B" scripts/test.sh RenderCoalescerTests`. Expected: `** TEST SUCCEEDED **` three times.
- [ ] **Step 5: Commit** `git add OpenCam OpenCamTests && git commit -m "feat: count a histogram of each rendered preview off the main actor"`

---

### Task 5: The curve editor

**Pre-flight corrections (controller, 2026-11-11; these override the text below):**
- `EditorLayout.minPanelHeight(for:)` returns 340 for `.curve` only in this task (`.grading` does not exist yet; Task 8 adds it). It replaces `EditorView`'s existing `private static let minPanelHeight` (do not keep both).
- `OpenCamTests/EditorLayoutTests.swift` is not modified; the `minPanelHeight` and geometry expectations live in `CurveEditingTests` as written. The `side(for: 381 x 300) == 232` line is a formula check, not the real folded size.
- `ScrollingPicker` uses `.scrollBounceBehavior(.basedOnSize, axes: .horizontal)` (the default axes are vertical only).
- `moving`: the first point's x is clamped to `0...(next.x − minGap)`, the last point's to `(previous.x + minGap)...1`, inner points between `previous.x + minGap` and `next.x − minGap`, compared in integer thousandths like Task 3's normalisation. Add to `dragsNeverCrossANeighbourAndTheEndsStay`: a point dragged to exactly its neighbour's x + 0.01 is kept.
- `applyLaunch`: seed formats, seed the study look, one `library.reload()`, then the launch push.
- Step 7 (tap and drag) is run by a separate verifier after review, not by the implementer. Step 8 commits without it.

**Files:**
- Create: `OpenCam/Edit/CurveHit.swift`, `OpenCam/Edit/CurveDrag.swift`, `OpenCam/Edit/ToneCurve+Editing.swift`, `OpenCam/UI/Editor/CurveGeometry.swift`, `OpenCam/UI/Editor/CurveCanvas.swift`, `OpenCam/UI/Editor/CurvePanel.swift`, `OpenCam/UI/Editor/ScrollingPicker.swift`
- Modify: `OpenCam/Edit/EditorGroup.swift` (`case light, colour, curve, detail, effects, looks`; title "Curve"; `curve.keys == []`), `OpenCam/Edit/EditorLayout.swift` (`minPanelHeight(for:)`), `OpenCam/UI/Editor/EditorPanel.swift` (the group picker becomes a `ScrollingPicker`; `.curve` shows `CurvePanel`), `OpenCam/UI/Editor/EditorView.swift` (`pictureHeight` uses `EditorLayout.minPanelHeight(for: model.group)`), `OpenCam/UI/Editor/EditorModel.swift`, `OpenCam/UI/Editor/EditorScreen.swift`, `OpenCam/UI/Library/LibraryView.swift`, `OpenCam/Library/LookSeeder.swift`, `OpenCam/App/LaunchConfig.swift` (own step)
- Test: `OpenCamTests/CurveEditingTests.swift`; Modify `OpenCamTests/AdjustmentsTests.swift` (the E1 group-title line becomes `["Light", "Colour", "Curve", "Detail", "Effects", "Looks"]`), `OpenCamTests/EditorLayoutTests.swift`, `OpenCamTests/LaunchConfigTests.swift`

**Interfaces:**
- Consumes: Task 3 `ToneCurve`, `ToneCurves`, `CurveChannel`, `CurvePoint`, `Adjustments.curves`; Task 4 `PictureHistogram.heights(_:)`, `EditorModel.histogram`; E1 `EditorModel` (`adjustments`, `applyLook(_:)`, `lookName`, `hasUnsavedChanges`, `lastRenderPixelSize`, `previewRenderCount`, `renderedAdjustments`, `waitForPreview()`), `EditorFixture.make(width:height:)`, `LookStore`, `LookSeeder`, `LaunchConfig`, `Theme.Space`. SwiftUI (checked in the SDK): `Canvas`, `DragGesture(minimumDistance:coordinateSpace:)`, `SpatialTapGesture(count:)`, `simultaneousGesture(_:including:)`, `highPriorityGesture(_:including:)`. No Pencil-specific API: Pencil touches arrive through the same `DragGesture`.
- Produces:

```swift
nonisolated enum CurveHit: Equatable, Sendable { case point(Int), curve, none }
extension ToneCurve {   // all in normalised units, x and y 0...1
    /// The nearest point within `radius`; else `.curve` when |value(at: x) − y| ≤ radius and x is between the end points; else `.none`.
    func hit(_ location: CurvePoint, radius: Double) -> CurveHit
    /// A point at (x, value(at: x)), so the picture does not change; nil at maxPoints, within minGap of a point, or outside the ends.
    func inserting(at x: Double) -> (curve: ToneCurve, index: Int)?
    /// x kept at least minGap from its neighbours (the first point 0...next, the last previous...1), y 0...1, both snapped.
    func moving(_ index: Int, to location: CurvePoint) -> ToneCurve
    func removing(_ index: Int) -> ToneCurve          // the first and last points are never removed: returns self
}
nonisolated struct CurveDrag: Equatable, Sendable {
    let original: ToneCurve; let index: Int
    /// `.point(i)` drags i; `.curve` inserts a point and drags it; `.none` is nil (nothing happens).
    static func begin(on curve: ToneCurve, at location: CurvePoint, radius: Double) -> CurveDrag?
    /// The curve while dragging by `translation` (normalised, y up). An inner point whose target is more than `margin` outside 0...1 on either axis is left out (removed on release); the ends clamp instead.
    func curve(translation: CurvePoint, margin: Double) -> ToneCurve }
nonisolated struct CurveGeometry: Equatable {
    static let inset: CGFloat = 12, hitRadius: CGFloat = 22, removeMargin: CGFloat = 24
    let side: CGFloat                                    // the canvas is side x side; the plot is inset by 12 pt on every edge
    func viewPoint(_ p: CurvePoint) -> CGPoint           // (0, 0) at bottom left of the plot
    func curvePoint(_ v: CGPoint) -> CurvePoint          // unclamped
    var hitRadius: Double { get }                        // 22 pt in normalised units: 22 / (side − 24)
    var removeMargin: Double { get }
    static func side(for panel: CGSize) -> CGFloat       // min(width − 32, height − 68), at least 0
}
struct CurveCanvas: View { @Binding var curve: ToneCurve; let channel: CurveChannel; let histogram: PictureHistogram? }
    // Canvas: a .quaternary plot, quarter grid lines, the histogram (RGB: luma white 0.25 opacity, red, green and blue at 0.3 with .plusLighter; a colour channel: its own bins only), a dashed diagonal, the curve as a 2 pt line in the channel's colour (RGB: .primary) sampled every 2 pt, points as 10 pt circles, the dragged one in Theme.accent and drawn faded while it would be removed. Gestures on the canvas: .highPriorityGesture(DragGesture(minimumDistance: 0)) driving CurveDrag (begin at the start location, curve(translation:) on change and on end); .simultaneousGesture(SpatialTapGesture(count: 2)) removing a hit point. Accessibility: label "<Channel> curve", value "<n> points", action "Reset".
struct CurvePanel: View { @Bindable var model: EditorModel }
    // A row: system segmented Picker "Curve channel" (labels hidden) over CurveChannel.allCases, and Button "Reset" (disabled while the channel is identity); then the CurveCanvas, side CurveGeometry.side(for:) of the space left.
struct ScrollingPicker<Value: Hashable>: View { let title: String; @Binding var selection: Value; let options: [Value]; let label: (Value) -> String }
    // A system segmented Picker, .fixedSize(), in ScrollView(.horizontal) with hidden indicators and .scrollBounceBehavior(.basedOnSize), padded by Theme.Space.l, so segments keep their full titles; .defaultScrollAnchor(.trailing) when the selection is in the last half of `options`, else .leading.
// EditorLayout: static func minPanelHeight(for group: EditorGroup) -> CGFloat   // 340 for .curve and .grading, else 240
// EditorModel: var curveChannel: CurveChannel = .master; func resetCurve(_ channel: CurveChannel)
// EditorModel.init(item:edits:looks:group:renderer:exporter:renderPreview:makeHistogram:launchLook:), launchLook: String? = nil: after a successful load(), the look in `looks` with exactly that name is applied through applyLook(_:), unsaved.
// EditorScreen.init(item:library:group:lookName:onDone:), lookName: String? = nil
nonisolated extension LookSeeder {
    static let colourStudyName = "Colour study"
    static let colourStudy: Adjustments   // master [(0, 0.06), (0.25, 0.2), (0.75, 0.82), (1, 0.97)], blue [(0, 0.04), (1, 1)]; Tasks 7 and 8 add theirs
    static func seedColourStudy(into store: LookStore) throws(LookStoreError) -> Look?   // nil when a look of that name exists
}
// LaunchConfig.seedsStudyLook: Bool (-seedStudy on, Simulator only)   LaunchConfig.editorLookName: String? (-editorLook <name>); both set isScripted
```

- [ ] **Step 1: Write the failing tests**

```swift
// OpenCamTests/CurveEditingTests.swift
@MainActor @Suite struct CurveEditingTests {
    let s = ToneCurve(points: [CurvePoint(x: 0, y: 0), CurvePoint(x: 0.5, y: 0.6), CurvePoint(x: 1, y: 1)])
    @Test func hitsPointsThenTheCurve() {
        #expect(s.hit(CurvePoint(x: 0.52, y: 0.61), radius: 0.05) == .point(1)); #expect(s.hit(CurvePoint(x: 0.25, y: 0.33), radius: 0.05) == .curve)     // value 0.315
        #expect(s.hit(CurvePoint(x: 0.25, y: 0.6), radius: 0.05) == .none); #expect(s.hit(CurvePoint(x: 0.99, y: 0.99), radius: 0.05) == .point(2)) }
    @Test func aTapOnTheCurveAddsAPointWithoutChangingThePicture() throws {
        let drag = try #require(CurveDrag.begin(on: s, at: CurvePoint(x: 0.25, y: 0.32), radius: 0.05)); let added = drag.curve(translation: CurvePoint(x: 0, y: 0), margin: 0.1)
        #expect(added.points.count == 4); #expect(added.points[1] == CurvePoint(x: 0.25, y: 0.315))
        for i in 0...20 { let x = Float(i) / 20; #expect(abs(added.value(at: x) - s.value(at: x)) < 0.01) }   // new tangents: within 0.01
        #expect(CurveDrag.begin(on: s, at: CurvePoint(x: 0.25, y: 0.9), radius: 0.05) == nil) }
    @Test func dragsNeverCrossANeighbourAndTheEndsStay() throws {   // Review Focus 4
        let drag = try #require(CurveDrag.begin(on: s, at: CurvePoint(x: 0.5, y: 0.6), radius: 0.05))
        #expect(drag.curve(translation: CurvePoint(x: 0.58, y: 0.2), margin: 0.1).points[1] == CurvePoint(x: 0.99, y: 0.8))
        #expect(drag.curve(translation: CurvePoint(x: -0.55, y: 0), margin: 0.1).points[1] == CurvePoint(x: 0.01, y: 0.6))
        #expect(drag.curve(translation: CurvePoint(x: 0.7, y: 0), margin: 0.1).points.count == 2)          // past the side margin: removed
        #expect(drag.curve(translation: CurvePoint(x: 0, y: -0.75), margin: 0.1).points.count == 2)        // off the bottom: removed
        #expect(drag.curve(translation: CurvePoint(x: 0, y: -0.65), margin: 0.1).points[1].y == 0)         // inside the margin: clamped
        let end = try #require(CurveDrag.begin(on: s, at: CurvePoint(x: 0, y: 0), radius: 0.05)); let lifted = end.curve(translation: CurvePoint(x: -0.5, y: -0.5), margin: 0.1)
        #expect(lifted.points.count == 3); #expect(lifted.points[0] == CurvePoint(x: 0, y: 0))
        #expect(end.curve(translation: CurvePoint(x: 0.7, y: 0.1), margin: 0.1).points[0] == CurvePoint(x: 0.49, y: 0.1))
        #expect(s.removing(0) == s); #expect(s.removing(2) == s); #expect(s.removing(1) == .identity) }
    @Test func geometryAndSizes() {
        let g = CurveGeometry(side: 236); #expect(g.viewPoint(CurvePoint(x: 0, y: 0)) == CGPoint(x: 12, y: 224)); #expect(g.viewPoint(CurvePoint(x: 1, y: 1)) == CGPoint(x: 224, y: 12))
        #expect(abs(g.hitRadius - 22.0 / 212) < 1e-9); #expect(CurveGeometry.side(for: CGSize(width: 381, height: 300)) == 232)    // folded portrait
        #expect(CurveGeometry.side(for: CGSize(width: 320, height: 384)) == 288)    // folded landscape, open
        #expect(EditorLayout.minPanelHeight(for: .curve) == 340); #expect(EditorLayout.minPanelHeight(for: .light) == 240) }
    @Test func curveDragRendersTheProxyOnlyThroughTheCoalescer() async throws {   // Review Focus 5
        let (model, _, _) = try await EditorFixture.make(width: 4096, height: 3072); let before = model.previewRenderCount
        let drag = try #require(CurveDrag.begin(on: model.adjustments.curves.master, at: CurvePoint(x: 0.5, y: 0.5), radius: 0.05))
        for step in 1...30 { model.adjustments.curves.master = drag.curve(translation: CurvePoint(x: 0, y: Double(step) / 100), margin: 0.1) }
        await model.waitForPreview(); #expect(model.previewRenderCount - before <= 2); #expect(model.renderedAdjustments == model.adjustments)
        #expect(model.lastRenderPixelSize == CGSize(width: 2048, height: 1536)) }
    @Test func resetCurveAndLaunchLook() async throws {
        let (model, _, looks) = try await EditorFixture.make(width: 64, height: 48)
        model.adjustments.curves.red = s; model.resetCurve(.red); #expect(model.adjustments.curves.red.isIdentity)
        _ = try LookSeeder.seedColourStudy(into: looks); #expect(try LookSeeder.seedColourStudy(into: looks) == nil)
        #expect(LookSeeder.colourStudy.curves.master.points.count == 4); #expect(LookSeeder.colourStudy.hasColourChanges); let captures = try TestFiles.directory()
        _ = try TestFiles.writeJPEG(width: 64, height: 48, rgb: SIMD3(0.5, 0.5, 0.5), to: captures.appending(path: "OC_0001.JPG"))
        guard let item = LibraryScanner.items(in: captures).first else { throw TestFileError.bitmapUnavailable }
        let launched = EditorModel(item: item, edits: EditStore(directory: captures), looks: looks, launchLook: "Colour study"); await launched.load()
        #expect(launched.adjustments == LookSeeder.colourStudy); #expect(launched.lookName == "Colour study"); #expect(launched.hasUnsavedChanges) } }
// Added to LaunchConfigTests
@Test func parsesTheStudyFlags() {
    let c = LaunchConfig.parse(["app", "-screen", "editor", "-editorGroup", "curve", "-seedStudy", "on", "-editorLook", "Colour study"])
    #expect(c.editorGroup == .curve); #expect(c.seedsStudyLook); #expect(c.editorLookName == "Colour study"); #expect(c.isScripted)
    #expect(LaunchConfig.parse(["app", "-editorLook", "X"]).isScripted); #expect(LaunchConfig.parse(["app", "-seedStudy", "on"]).isScripted) }
```

- [ ] **Step 2: Run to see them fail.** `OPENCAM_SIM_NAME="OpenCam Dev B" scripts/test.sh CurveEditingTests`. Expected: build error `cannot find 'CurveDrag' in scope`.
- [ ] **Step 3: Implement the model, the geometry and the views.** Every point edit writes `model.adjustments.curves[model.curveChannel]`, so it renders through the coalescer like a slider. The canvas is not inside the panel's vertical `ScrollView`. Its frame is `side x side`, centred.
- [ ] **Step 4: The launch flags (the only shared file in this step).** `OpenCam/App/LaunchConfig.swift`: `seedsStudyLook`, `editorLookName`, the doc comment, and `-editorGroup light|colour|curve|detail|effects|looks` in its comment. `LibraryView.applyLaunch` seeds "Colour study" into `library.lookStore` (Simulator only, logged like the formats) and passes `launch.editorLookName` to the launch push only (a new `@State editorLookName`, nil for a tap); `EditorScreen` passes it on as `launchLook`.
- [ ] **Step 5: Run to see them pass.** `OPENCAM_SIM_NAME="OpenCam Dev B" scripts/test.sh` with each of `CurveEditingTests`, `AdjustmentsTests`, `EditorLayoutTests`, `LaunchConfigTests`, `EditorModelTests`, `LibraryLaunchTests`. Expected: `** TEST SUCCEEDED **` six times.
- [ ] **Step 6: Screenshots**

```bash
export SHOT_DIR=docs/screenshots/e3
OPENCAM_SIM_NAME="OpenCam Dev B" SHOT_FRESH=1 scripts/shot.sh e3-editor-light-v -orientation portrait -screen editor -seedSamples on
for o in portrait landscape; do s=v; [[ $o == landscape ]] && s=h
  OPENCAM_SIM_NAME="OpenCam Dev B" scripts/shot.sh "e3-editor-curve-$s" -orientation "$o" -screen editor -seedSamples on -seedStudy on -editorLook "Colour study" -editorGroup curve
done
```

Pass when: `e3-editor-light-v` matches `docs/screenshots/e1/e1-editor-light-v.png` except the group picker (every title whole, scrollable sideways); `e3-editor-curve-v` shows the picker scrolled to "Curve", "RGB" selected, "Reset" enabled, a square canvas at least 220 pt (660 px) a side, the histogram behind a four-point S curve whose black end is lifted, the picture matte; `-h` the same at 288 pt beside the picture, nothing clipped.
- [ ] **Step 7: Tap and drag test, folded then open** (one action, wait, screenshot, look; write the outcome of each). Launch `-screen editor -seedSamples on -editorGroup curve`. (1) Tap the diagonal at the canvas centre: a third point appears on the line, the picture is unchanged, "Reset" enables. (2) Drag that point up 40 pt (`touch_path`): the curve bows up, the picture brightens, the histogram moves right. (3) Drag it right to the canvas's right edge: it stops just short of the end point. (4) Drag it 60 pt below the canvas and release: it is gone, the curve is straight. (5) Add a point, double-tap it: removed. (6) Drag the top-right end point down 30 pt: whites dim; it cannot be removed by dragging off. (7) Choose "Red", drag the middle up: the picture reddens; "RGB" still shows its own curve. (8) "Reset": Red is straight, RGB keeps its curve. (9) Done, reopen the photo: the curves are as left. (10) In portrait, drag vertically on the canvas: the panel does not scroll. Repeat 1, 2, 4 and 7 near the canvas's right edge, beside the system strip. Pencil is checked by Tanner on the device.
- [ ] **Step 8: Commit** `git add OpenCam OpenCamTests docs/screenshots/e3 && git commit -m "feat: add the Curve group with a point curve editor over the histogram"`

---

### Task 6: Colour mixer and grading maths

**Pre-flight corrections (controller, 2026-11-11; these override the text below):**
- `OpenCam/Render/ColourTint.swift` is inside the fence.

The draft's Task 1 maths, with a luminance per region and Blending added to grading.

**Files:**
- Create: `OpenCam/Edit/ColourBand.swift`, `OpenCam/Render/ColourTint.swift`, `OpenCam/Render/ColourMath+Tools.swift`
- Modify: `OpenCam/Render/ColourMath.swift` (only: the two `clamp01` helpers drop `private`)
- Test: `OpenCamTests/ColourToolMathTests.swift`

**Interfaces:**
- Consumes: E1 `ColourMath.luma(_:)`, `ColourMath.clamp01`.
- Produces:

```swift
nonisolated enum ColourBand: String, CaseIterable, Sendable {
    case red, orange, yellow, green, aqua, blue, purple, magenta
    var title: String { get }      // "Red" ... "Magenta"
    var centre: Float { get }      // degrees: 0, 30, 60, 120, 180, 240, 270, 300
    var index: Int { get }         // 0...7
}
nonisolated struct ColourTint: Sendable, Equatable {
    var hue: Float; var saturation: Float; var luminance: Float     // degrees 0...360; 0...1; −1...1
    init(hue: Float, saturation: Float, luminance: Float = 0)
    static let none = ColourTint(hue: 0, saturation: 0) }
extension ColourMath {
    static let mixHueReach: Float = 30, mixLuminanceReach: Float = 0.5
    static let gradingStrength: Float = 0.25, gradingLuminanceReach: Float = 0.2, balanceReach: Float = 0.25
    static func hsv(_ rgb: SIMD3<Float>) -> SIMD3<Float>                      // (hue 0..<360, saturation, value); hue 0 for grey
    static func rgb(hue: Float, saturation: Float, value: Float) -> SIMD3<Float>
    static func bandWeights(hue: Float) -> SIMD8<Float>                       // ColourBand.allCases order
    static func mix(_ rgb: SIMD3<Float>, hue: SIMD8<Float>, saturation: SIMD8<Float>, luminance: SIMD8<Float>) -> SIMD3<Float>
    static func regionWeights(luma: Float, balance: Float, blending: Float) -> SIMD3<Float>   // (shadows, midtones, highlights)
    static func grade(_ rgb: SIMD3<Float>, shadows: ColourTint, midtones: ColourTint, highlights: ColourTint,
                      balance: Float, blending: Float) -> SIMD3<Float> }
```

Formulas, exact (doc comments carry them):
- **HSV**: `V = max`, `C = max − min`, `S = C/V` (0 when `V == 0`); `H = 60·((g − b)/C mod 6)` when max is red, `60·((b − r)/C + 2)` green, `60·((r − g)/C + 4)` blue, 0 when `C == 0`. Back: `C = V·S`, `X = C·(1 − |(H/60) mod 2 − 1|)`, `m = V − C`, six sectors.
- **Band weights**: linear tents between neighbouring centres (`c_8 = 360` wraps to red): for `H` in `[c_i, c_{i+1})`, `t = (H − c_i)/(c_{i+1} − c_i)`, `w_i = 1 − t`, `w_{i+1 mod 8} = t`, others 0.
- **Mixer**: `(H, S, V) = hsv(x)`, `w = bandWeights(H)`; `H' = (H + mixHueReach·Σw·hue) mod 360`; `S' = clamp01(S·(1 + Σw·saturation))`; `V' = clamp01(V·(1 + mixLuminanceReach·S·Σw·luminance))`; result `rgb(H', S', V')`. A grey is returned unchanged.
- **Regions**: pivot `p = 0.5 + balanceReach·balance`; exponent `k = 2·2^(−blending)` (2 at 0, 1 at +1, 4 at −1); `w_s = clamp01(1 − Y/p)^k`, `w_h = clamp01((Y − p)/(1 − p))^k`, `w_m = 1 − w_s − w_h`.
- **Grading**: `Y = luma(x)`, weights as above; for each region `c = rgb(hue, 1, 1)`, `o = c − luma(c)`; `x' = clamp01(x + gradingStrength·Σ w_r·saturation_r·o_r + gradingLuminanceReach·Σ w_r·luminance_r)`.
- [ ] **Step 1: Write the failing tests**

```swift
// OpenCamTests/ColourToolMathTests.swift
@Suite struct ColourToolMathTests {
    let red = SIMD3<Float>(0.75, 0.25, 0.25), blue = SIMD3<Float>(0.25, 0.25, 0.75), green = SIMD3<Float>(0.25, 0.75, 0.25)
    let grey = SIMD3<Float>(repeating: 0.5), zero8 = SIMD8<Float>(repeating: 0)
    func maxDiff(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float { ((a - b) * (a - b)).squareRoot().max() }
    func only(_ band: ColourBand, _ v: Float) -> SIMD8<Float> { var s = SIMD8<Float>(repeating: 0); s[band.index] = v; return s }
    func mix(_ x: SIMD3<Float>, hue: SIMD8<Float>? = nil, sat: SIMD8<Float>? = nil, lum: SIMD8<Float>? = nil) -> SIMD3<Float> {
        ColourMath.mix(x, hue: hue ?? zero8, saturation: sat ?? zero8, luminance: lum ?? zero8) }
    func grade(_ x: SIMD3<Float>, s: ColourTint = .none, m: ColourTint = .none, h: ColourTint = .none, balance: Float = 0, blending: Float = 0) -> SIMD3<Float> {
        ColourMath.grade(x, shadows: s, midtones: m, highlights: h, balance: balance, blending: blending) }
    @Test func hsvBandsAndWeights() {
        #expect(maxDiff(ColourMath.hsv(red), SIMD3(0, 2.0 / 3, 0.75)) < 1e-6); #expect(maxDiff(ColourMath.hsv(grey), SIMD3(0, 0, 0.5)) < 1e-6)
        #expect(maxDiff(ColourMath.rgb(hue: 30, saturation: 2.0 / 3, value: 0.75), SIMD3(0.75, 0.5, 0.25)) < 1e-6)
        #expect(ColourBand.allCases.map(\.centre) == [0, 30, 60, 120, 180, 240, 270, 300]); #expect(ColourMath.bandWeights(hue: 15) == only(.red, 0.5) + only(.orange, 0.5))
        #expect(ColourMath.bandWeights(hue: 330) == only(.magenta, 0.5) + only(.red, 0.5))
        for tenth in 0..<3600 {
            let w = ColourMath.bandWeights(hue: Float(tenth) / 10); #expect(abs(w.sum() - 1) < 1e-5); #expect((0..<8).filter { w[$0] > 0 }.count <= 2) } }
    @Test func mixerIsIdentityAtZeroAndStaysInItsBand() {
        for x in [red, blue, green, grey, SIMD3(0.03, 0.9, 0.4), .zero, .one] { #expect(maxDiff(mix(x), x) < 1e-5) }
        #expect(maxDiff(mix(red, hue: only(.red, 1)), SIMD3(0.75, 0.5, 0.25)) < 1e-5); #expect(maxDiff(mix(SIMD3(0.75, 0.375, 0.25), hue: only(.red, 1)), SIMD3(0.75, 0.5, 0.25)) < 1e-5)
        #expect(maxDiff(mix(blue, hue: only(.red, 1)), blue) < 1e-6); #expect(maxDiff(mix(blue, hue: only(.purple, 1)), blue) < 1e-6)
        #expect(maxDiff(mix(red, sat: only(.red, -1)), SIMD3(0.75, 0.75, 0.75)) < 1e-5); #expect(maxDiff(mix(red, lum: only(.red, -1)), SIMD3(0.5, 1.0 / 6, 1.0 / 6)) < 1e-5)
        let all = SIMD8<Float>(repeating: 1); #expect(maxDiff(mix(grey, hue: all, sat: all, lum: all), grey) < 1e-6) }
    @Test func gradingAtZeroIsTheIdentityAndRegionsKeepTheirEnds() {
        for hue: Float in [0, 90, 200, 330] { for b: Float in [-1, 0, 1] { for x in [red, grey, .zero, .one] {
            let t = ColourTint(hue: hue, saturation: 0); #expect(grade(x, s: t, m: t, h: t, balance: b, blending: b) == x) } } }
        for b: Float in [-1, 0, 1] {
            #expect(grade(.one, s: ColourTint(hue: 220, saturation: 1, luminance: -1), balance: b, blending: b) == .one)
            #expect(grade(.zero, h: ColourTint(hue: 40, saturation: 1, luminance: 1), balance: b, blending: b) == .zero) } }
    @Test func midtonesTintKeepsLumaAndLuminanceLifts() {
        let tinted = grade(grey, m: ColourTint(hue: 0, saturation: 1)); #expect(maxDiff(tinted, SIMD3(0.69685, 0.44685, 0.44685)) < 1e-4); #expect(abs(ColourMath.luma(tinted) - 0.5) < 1e-5)
        #expect(maxDiff(grade(grey, m: ColourTint(hue: 0, saturation: 0, luminance: 1)), SIMD3(repeating: 0.7)) < 1e-5) }
    @Test func balanceAndBlendingMoveTheSplit() {
        #expect(maxDiff(ColourMath.regionWeights(luma: 0.5, balance: 0, blending: 0), SIMD3(0, 1, 0)) < 1e-6)
        #expect(maxDiff(ColourMath.regionWeights(luma: 0.5, balance: -1, blending: 0), SIMD3(0, 8.0 / 9, 1.0 / 9)) < 1e-5)
        #expect(maxDiff(ColourMath.regionWeights(luma: 0.25, balance: 0, blending: 0), SIMD3(0.25, 0.75, 0)) < 1e-6)
        #expect(maxDiff(ColourMath.regionWeights(luma: 0.25, balance: 0, blending: 1), SIMD3(0.5, 0.5, 0)) < 1e-6)
        #expect(maxDiff(ColourMath.regionWeights(luma: 0.25, balance: 0, blending: -1), SIMD3(0.0625, 0.9375, 0)) < 1e-6)
        #expect(abs(grade(grey, h: ColourTint(hue: 0, saturation: 1), balance: -1).x - 0.52187) < 1e-4) } }
```

- [ ] **Step 2: Run to see them fail.** `OPENCAM_SIM_NAME="OpenCam Dev B" scripts/test.sh ColourToolMathTests`. Expected: `cannot find 'ColourBand' in scope`.
- [ ] **Step 3: Implement** with the formulas exactly as above. `bandWeights` takes a hue already in 0..<360.
- [ ] **Step 4: Run to see them pass.** `OPENCAM_SIM_NAME="OpenCam Dev B" scripts/test.sh ColourToolMathTests && OPENCAM_SIM_NAME="OpenCam Dev B" scripts/test.sh ColourMathTests`. Expected: `** TEST SUCCEEDED **` twice.
- [ ] **Step 5: Commit** `git add OpenCam OpenCamTests && git commit -m "feat: add the maths of the colour mixer and colour grading"`

---

### Task 7: The colour mixer in the table and the editor

**Pre-flight corrections (controller, 2026-11-11; these override the text below):**
- `encode(to:)` writes the 14 E1 keys always (as today) and each added key only when it is not 0 (`toolValues` never holds a 0), plus `"curves"` when not identity: not every key in `allCases`. Decoding treats a missing key as 0. This keeps every existing edit's JSON, and so its thumbnail cache key, unchanged.
- Stage 8 goes into `ColourMath.apply`'s stage-list doc comment; clamp is renumbered. The "anything to do" check before stage 8 is the cheapest one available (for example `toolValues.isEmpty` before reading the 24 keys).
- Step 6 (tap and drag) is run by a separate verifier after review, not by the implementer.

**Files:**
- Create: `OpenCam/UI/Editor/MixPanel.swift`
- Modify: `OpenCam/Edit/AdjustmentKey.swift`, `OpenCam/Edit/Adjustments.swift` (scalar storage below), `OpenCam/Edit/ColourBand.swift` (its keys), `OpenCam/Edit/EditorGroup.swift` (`case light, colour, curve, mix, detail, effects, looks`, title "Mix"), `OpenCam/Render/ColourMath.swift` (stage 8), `OpenCam/UI/Editor/EditorPanel.swift`, `OpenCam/UI/Editor/EditorModel.swift` (`var mixBand: ColourBand = .red`, never saved), `OpenCam/Library/LookSeeder.swift`
- Test: `OpenCamTests/MixerTests.swift`; Modify `OpenCamTests/AdjustmentsTests.swift` (E1 titles line uses `AdjustmentKey.allCases.prefix(14)`; groups line gains "Mix" after "Curve"), `OpenCamTests/ColourKeyTests.swift`

**Interfaces:**
- Consumes: Task 6 `ColourBand`, `ColourMath.mix`; Task 5 `ScrollingPicker`, `LookSeeder.colourStudy`; E1 `AdjustmentSlider(key:value:onReset:)`, `EditorModel.reset(_:)`, `CallCounter`.
- Produces:

```swift
// AdjustmentKey, after the fourteen E1 cases, raw values are the JSON keys:
case mixRedHue, mixRedSaturation, mixRedLuminance, mixOrangeHue, mixOrangeSaturation, mixOrangeLuminance,
     mixYellowHue, mixYellowSaturation, mixYellowLuminance, mixGreenHue, mixGreenSaturation, mixGreenLuminance,
     mixAquaHue, mixAquaSaturation, mixAquaLuminance, mixBlueHue, mixBlueSaturation, mixBlueLuminance,
     mixPurpleHue, mixPurpleSaturation, mixPurpleLuminance, mixMagentaHue, mixMagentaSaturation, mixMagentaLuminance
// title "<Band> hue|saturation|luminance"; range −100...100; step 1; isColour true; group .mix; valueText by the E1 rule ("+20").
extension ColourBand { var hueKey: AdjustmentKey; var saturationKey: AdjustmentKey; var luminanceKey: AdjustmentKey
                       var keys: [AdjustmentKey]                // [hue, saturation, luminance]
                       var swatch: SIMD3<Float> }               // ColourMath.rgb(hue: centre, saturation: 0.8, value: 0.9)
// EditorGroup.mix.keys == ColourBand.allCases.flatMap(\.keys)
struct MixPanel: View { @Bindable var model: EditorModel }
    // "Colour band": a Grid of 2 rows x 4 system Buttons (min height 44), each the band's title, .buttonStyle(.bordered) tinted with its swatch, the selected one .borderedProminent and .accessibilityAddTraits(.isSelected); then three AdjustmentSliders for model.mixBand.keys; all in the panel's ScrollView.
```

`Adjustments` storage (the draft's design): the fourteen E1 stored properties stay. Every key added from here on lives in `private var toolValues: [AdjustmentKey: Double] = [:]`, which never holds a zero (the setter removes a key set to 0), so the synthesized `Hashable` and `Equatable` stay correct and a value moved back to 0 equals `Adjustments()`. The subscript keeps its E1 switch and reads and writes `toolValues` in its `default:` branch, clamping as before. Coding uses a private `struct` `CodingKey` built from `key.rawValue` plus "curves"; decoding keeps its rule (every key optional, unknown keys ignored, values clamped); `encode(to:)` writes every key in `allCases`, zeros included, and "curves" when not identity. Stage 8 in `apply` (skipped when every mixer key is 0) calls `mix` with `SIMD8`s built in `ColourBand.allCases` order, each value `/ 100`. `LookSeeder.colourStudy` gains `mixRedHue 15, mixRedSaturation 30, mixGreenHue -20, mixBlueSaturation 20, mixBlueLuminance -30`.

- [ ] **Step 1: Write the failing tests**

```swift
// OpenCamTests/MixerTests.swift
@MainActor @Suite struct MixerTests {
    @Test func keysTitlesAndRoundTrip() throws {
        #expect(AdjustmentKey.allCases.count == 38); #expect(EditorGroup.mix.keys.count == 24); #expect(ColourBand.red.keys == [.mixRedHue, .mixRedSaturation, .mixRedLuminance])
        #expect(AdjustmentKey.mixMagentaLuminance.title == "Magenta luminance"); #expect(AdjustmentKey.mixAquaHue.range == -100...100)
        let a = Adjustments().setting(.mixRedHue, to: 150).setting(.mixBlueLuminance, to: -30)
        #expect(a[.mixRedHue] == 100); #expect(try JSONDecoder().decode(Adjustments.self, from: JSONEncoder().encode(a)) == a)
        #expect(Adjustments().setting(.mixRedHue, to: 20).setting(.mixRedHue, to: 0) == Adjustments())
        for key in EditorGroup.mix.keys {
            let moved = Adjustments().setting(key, to: 50); #expect(key.isColour); #expect(!moved.isIdentity); #expect(moved.hasColourChanges); #expect(!moved.matches(Adjustments()))
            #expect(moved.matches(Adjustments().setting(key, to: 50.4))) } }
    @Test func stageEightRunsInsideApplyAfterSaturation() {
        let shifted = ColourMath.apply(Adjustments().setting(.mixRedHue, to: 100), to: SIMD3(0.75, 0.25, 0.25))
        #expect(abs(shifted.x - 0.75) < 1e-4); #expect(abs(shifted.y - 0.5) < 1e-4); #expect(abs(shifted.z - 0.25) < 1e-4)
        let grey = Adjustments().setting(.saturation, to: -100).setting(.mixRedSaturation, to: 100)
        let out = ColourMath.apply(grey, to: SIMD3(0.8, 0.3, 0.3)); #expect(abs(out.x - out.y) < 1e-5) }   // a grey stays grey
    @Test func bandChoiceIsNotSaved() async throws {
        let (model, captures, looks) = try await EditorFixture.make(width: 64, height: 48); model.mixBand = .blue; model.adjustments[.mixBlueLuminance] = -30; #expect(model.save())
        guard let item = LibraryScanner.items(in: captures).first else { throw TestFileError.bitmapUnavailable }
        let reopened = EditorModel(item: item, edits: EditStore(directory: captures), looks: looks); await reopened.load()
        #expect(reopened.mixBand == .red); #expect(reopened.adjustments[.mixBlueLuminance] == -30); #expect(LookSeeder.colourStudy[.mixBlueLuminance] == -30) } }
// ColourKeyTests: colourKeys gains EditorGroup.mix.keys; samples gain one colour per band: ColourBand.allCases.map { ColourMath.rgb(hue: $0.centre, saturation: 0.6, value: 0.7) }
```

- [ ] **Step 2: Run to see them fail.** `OPENCAM_SIM_NAME="OpenCam Dev B" scripts/test.sh MixerTests`. Expected: `type 'AdjustmentKey' has no member 'mixRedHue'`.
- [ ] **Step 3: Implement the Interfaces.**
- [ ] **Step 4: Run to see them pass.** `OPENCAM_SIM_NAME="OpenCam Dev B" scripts/test.sh` with each of `MixerTests`, `AdjustmentsTests`, `ColourKeyTests`, `ColourMathTests`, `LookCompilerTests`, `EditStoreTests`, `EditorModelTests`. Expected: `** TEST SUCCEEDED **` seven times.
- [ ] **Step 5: Screenshots** `export SHOT_DIR=docs/screenshots/e3`, then `OPENCAM_SIM_NAME="OpenCam Dev B" SHOT_FRESH=1 scripts/shot.sh e3-editor-mix-v -orientation portrait -screen editor -seedSamples on -seedStudy on -editorLook "Colour study" -editorGroup mix` and the same without `SHOT_FRESH=1` as `e3-editor-mix-h -orientation landscape`. Pass when "Mix" is selected and visible in the picker, the eight band buttons show their colours with readable titles, Red is selected, and "Red hue" "+15", "Red saturation" "+30", "Red luminance" "0" show.
- [ ] **Step 6: Tap and drag test, folded then open.** (1) Tap "Blue": it becomes the selected button, the sliders read "Blue hue" "0", "Blue saturation" "+20", "Blue luminance" "-30". (2) Drag "Blue luminance" left: the sky in the scene darkens, the grass does not. (3) Double-tap the "Blue luminance" name row: "0". (4) Tap each of the eight buttons in turn, including the one nearest the system strip: each selects. (5) Scroll the panel by dragging between buttons and sliders.
- [ ] **Step 7: Commit** `git add OpenCam OpenCamTests docs/screenshots/e3 && git commit -m "feat: add the Mix group with eight colour bands"`

---

### Task 8: Colour grading wheels in the table and the editor

**Pre-flight corrections (controller, 2026-11-11; these override the text below):**
- `EditorLayout.minPanelHeight(for:)` gains `.grading` (340) in this task, with an expectation added beside the `.curve` one.
- `OpenCamTests/MixerTests.swift` is modified: its `AdjustmentKey.allCases.count == 38` line becomes `== 49`.
- Stage 9 goes into `ColourMath.apply`'s stage-list doc comment; clamp becomes 10.
- Step 6 (tap and drag) is run by a separate verifier after review, not by the implementer.

**Files:**
- Create: `OpenCam/Edit/GradingRegion.swift`, `OpenCam/UI/Editor/WheelGeometry.swift`, `OpenCam/UI/Editor/ColourWheel.swift`, `OpenCam/UI/Editor/GradingPanel.swift`
- Modify: `OpenCam/Edit/AdjustmentKey.swift`, `OpenCam/Edit/EditorGroup.swift` (`case light, colour, curve, mix, grading, detail, effects, looks`, title "Grading"), `OpenCam/Render/ColourMath.swift` (stage 9), `OpenCam/UI/Editor/AdjustmentSlider.swift` (`var title: String? = nil`, declared before `onReset`: the shown name when set; the accessibility label stays `key.title`), `OpenCam/UI/Editor/EditorPanel.swift`, `OpenCam/UI/Editor/EditorModel.swift`, `OpenCam/Library/LookSeeder.swift`
- Test: `OpenCamTests/GradingTests.swift`; Modify `OpenCamTests/AdjustmentsTests.swift` (groups line gains "Grading"), `OpenCamTests/ColourKeyTests.swift`

**Interfaces:**
- Consumes: Task 6 `ColourTint`, `ColourMath.grade`, `ColourMath.rgb`; Task 7 `toolValues` storage; Task 5 `EditorLayout.minPanelHeight(for:)` (already 340 for `.grading`); E1 `AdjustmentSlider`.
- Produces:

```swift
// AdjustmentKey, after the mixer keys:
case gradingShadowsHue, gradingShadowsSaturation, gradingShadowsLuminance, gradingMidtonesHue, gradingMidtonesSaturation,
     gradingMidtonesLuminance, gradingHighlightsHue, gradingHighlightsSaturation, gradingHighlightsLuminance, gradingBlending, gradingBalance
// ranges: hues 0...360, saturations 0...100, luminances, blending and balance −100...100; step 1; isColour true; group .grading. valueText: hues "210°" ("0°" at 0); others by the E1 rules.
nonisolated enum GradingRegion: String, CaseIterable, Sendable { case shadows, midtones, highlights
    var title: String; var hueKey: AdjustmentKey; var saturationKey: AdjustmentKey; var luminanceKey: AdjustmentKey }
nonisolated enum WheelGeometry {
    static let maxDiameter: CGFloat = 160
    static func diameter(forWidth width: CGFloat) -> CGFloat                   // min(160, ((width − 44) / 2).rounded(.down))
    /// Hue: the angle from the centre, 0 at the right, increasing clockwise on screen; saturation: distance / radius, capped at 100; both rounded to whole numbers; a saturation of 0 gives hue 0, so a puck at the centre is no edit.
    static func tint(at point: CGPoint, diameter: CGFloat) -> (hue: Double, saturation: Double)
    static func point(hue: Double, saturation: Double, diameter: CGFloat) -> CGPoint }
struct ColourWheel: View { let region: GradingRegion; @Bindable var model: EditorModel; let diameter: CGFloat }
    // Title row: region.title and "<hue>° · <saturation>". Canvas: a disc filled with a conic gradient of ColourMath.rgb(hue: h, saturation: 1, value: 1) every 30° (Display P3 colours) from 0 at the right, clockwise, under a radial gradient from white at the centre to clear at the rim, so the drawn colour at a point is the colour that point adds; a 16 pt puck with a 2 pt white ring. .highPriorityGesture(DragGesture(minimumDistance: 0)) sets hue and saturation from the touch (the puck jumps to the finger); .simultaneousGesture(SpatialTapGesture(count: 2)) calls model.resetWheel(region). Below: AdjustmentSlider(key: region.luminanceKey, title: "Luminance"). Accessibility: .accessibilityRepresentation with two system Sliders, "<Region> hue" and "<Region> saturation".
struct GradingPanel: View { @Bindable var model: EditorModel }
    // In the panel's ScrollView: Midtones centred; Shadows and Highlights side by side, 12 pt apart; then "Blending", "Balance".
// EditorModel: func resetWheel(_ region: GradingRegion)   // hue and saturation to 0; luminance keeps its own reset
```

Stage 9 in `apply` (skipped when every grading saturation and luminance is 0) calls `grade` with `ColourTint(hue: deg, saturation: s / 100, luminance: l / 100)` per region, `balance / 100` and `blending / 100`. `LookSeeder.colourStudy` gains `gradingShadowsHue 210, gradingShadowsSaturation 35, gradingHighlightsHue 45, gradingHighlightsSaturation 30, gradingMidtonesLuminance 5`.

- [ ] **Step 1: Write the failing tests**

```swift
// OpenCamTests/GradingTests.swift
@MainActor @Suite struct GradingTests {
    @Test func keysAndText() {
        #expect(AdjustmentKey.allCases.count == 49); #expect(EditorGroup.grading.keys.count == 11)
        #expect(EditorGroup.allCases.map(\.title) == ["Light", "Colour", "Curve", "Mix", "Grading", "Detail", "Effects", "Looks"])
        #expect(AdjustmentKey.gradingShadowsHue.range == 0...360); #expect(AdjustmentKey.gradingShadowsHue.valueText(210) == "210°")
        #expect(AdjustmentKey.gradingBlending.title == "Blending"); #expect(AdjustmentKey.gradingHighlightsLuminance.title == "Highlights luminance")
        #expect(GradingRegion.midtones.saturationKey == .gradingMidtonesSaturation) }
    @Test func wheelGeometry() {
        let d: CGFloat = 100; #expect(WheelGeometry.tint(at: CGPoint(x: 100, y: 50), diameter: d) == (0, 100))
        #expect(WheelGeometry.tint(at: CGPoint(x: 50, y: 100), diameter: d) == (90, 100))   // below the centre: clockwise
        #expect(WheelGeometry.tint(at: CGPoint(x: 0, y: 50), diameter: d) == (180, 100)); #expect(WheelGeometry.tint(at: CGPoint(x: 50, y: 0), diameter: d) == (270, 100))
        #expect(WheelGeometry.tint(at: CGPoint(x: 75, y: 50), diameter: d) == (0, 50)); #expect(WheelGeometry.tint(at: CGPoint(x: 200, y: 50), diameter: d) == (0, 100))
        #expect(WheelGeometry.tint(at: CGPoint(x: 50.1, y: 50.1), diameter: d) == (0, 0))   // saturation rounds to 0, so hue 0
        #expect(WheelGeometry.point(hue: 90, saturation: 50, diameter: d) == CGPoint(x: 50, y: 75))
        #expect(WheelGeometry.diameter(forWidth: 320) == 138); #expect(WheelGeometry.diameter(forWidth: 381) == 160) }
    @Test func stageNineRunsAfterSaturationAndBlendingAloneDoesNothing() {
        let toned = Adjustments().setting(.saturation, to: -100).setting(.gradingMidtonesHue, to: 30).setting(.gradingMidtonesSaturation, to: 50)
        let out = ColourMath.apply(toned, to: SIMD3(0.8, 0.4, 0.2)); #expect(out.x > out.z + 0.05)
        #expect(ColourMath.apply(Adjustments().setting(.gradingBlending, to: 80).setting(.gradingShadowsHue, to: 200), to: SIMD3(repeating: 0.5))
                == ColourMath.apply(Adjustments(), to: SIMD3(repeating: 0.5)))
        #expect(abs(ColourMath.apply(Adjustments().setting(.gradingMidtonesLuminance, to: 100), to: SIMD3(repeating: 0.5)).y - 0.7) < 1e-4) }
    @Test func resetWheelClearsHueAndSaturationOnly() async throws {
        let (model, _, _) = try await EditorFixture.make(width: 64, height: 48)
        model.adjustments[.gradingShadowsHue] = 210; model.adjustments[.gradingShadowsSaturation] = 35; model.adjustments[.gradingShadowsLuminance] = -10; model.resetWheel(.shadows)
        #expect(model.adjustments[.gradingShadowsHue] == 0); #expect(model.adjustments[.gradingShadowsSaturation] == 0)
        #expect(model.adjustments[.gradingShadowsLuminance] == -10); #expect(LookSeeder.colourStudy[.gradingShadowsHue] == 210) } }
// ColourKeyTests: colourKeys gains EditorGroup.grading.keys. A hue, Blending or Balance changes nothing while every grading saturation and luminance is 0, so each is moved over a partner:
static let partner: [AdjustmentKey: AdjustmentKey] = [.gradingShadowsHue: .gradingShadowsSaturation, .gradingMidtonesHue: .gradingMidtonesSaturation,
    .gradingHighlightsHue: .gradingHighlightsSaturation, .gradingBlending: .gradingShadowsSaturation, .gradingBalance: .gradingShadowsSaturation]
static func base(_ key: AdjustmentKey) -> Adjustments { partner[key].map { Adjustments().setting($0, to: 50) } ?? Adjustments() }
static func moved(_ key: AdjustmentKey) -> Adjustments { base(key).setting(key, to: key.range.upperBound / 2) }
// isRead compares apply(moved(key)) with apply(base(key)); the cache test builds base(key) first, then moved(key).
```

- [ ] **Step 2: Run to see them fail.** `OPENCAM_SIM_NAME="OpenCam Dev B" scripts/test.sh GradingTests`. Expected: `type 'AdjustmentKey' has no member 'gradingShadowsHue'`.
- [ ] **Step 3: Implement the Interfaces.**
- [ ] **Step 4: Run to see them pass.** `OPENCAM_SIM_NAME="OpenCam Dev B" scripts/test.sh` with each of `GradingTests`, `AdjustmentsTests`, `ColourKeyTests`, `ColourMathTests`, `ColourToolMathTests`, `MixerTests`, `EditorModelTests`. Expected: `** TEST SUCCEEDED **` seven times.
- [ ] **Step 5: Screenshots** `export SHOT_DIR=docs/screenshots/e3`, then `OPENCAM_SIM_NAME="OpenCam Dev B" SHOT_FRESH=1 scripts/shot.sh e3-editor-grading-v -orientation portrait -screen editor -seedSamples on -seedStudy on -editorLook "Colour study" -editorGroup grading` and the same without `SHOT_FRESH=1` as `e3-editor-grading-h -orientation landscape`. Pass when: Midtones on top, Shadows and Highlights below, each a full colour disc with its puck (Shadows toward blue at 210°, Highlights toward orange at 45°), readouts "210° · 35" and "45° · 30", each wheel 160 pt (480 px) folded portrait and 138 pt (414 px) beside the picture; Blending and Balance below, reachable by scrolling; the picture shows cooler shadows and warmer highlights.
- [ ] **Step 6: Tap and drag test, folded then open.** (1) Tap the right edge of the Midtones wheel: the puck jumps there, readout "0° · 100"-ish, the picture turns red. (2) Drag the puck in a circle (`touch_path`) through the bottom: the readout passes 90°, the picture's tint follows the colour under the puck. (3) Drag to the centre: "0° · 0", the picture is as before. (4) Double-tap the Shadows wheel: "0° · 0". (5) Drag "Luminance" under Highlights: highlights brighten. (6) Drag vertically on a wheel: the puck moves, the panel does not scroll; drag vertically between the wheels: the panel scrolls to Blending and Balance. (7) Drag "Blending" and "Balance" with a shadows tint set: the tinted range widens and moves. (8) Repeat 1 and 4 on the Highlights wheel, nearest the system strip. If the double-tap does not fire beside the drag, move the reset to a double-tap on the wheel's title row (the `AdjustmentSlider` pattern) and report it.
- [ ] **Step 7: Commit** `git add OpenCam OpenCamTests docs/screenshots/e3 && git commit -m "feat: add the Grading group with three colour wheels"`

---

### Task 9: One table check and E3 verification

**Pre-flight corrections (controller, 2026-11-11; these override the text below):**
- Step 4's sweep diffs against `$(git merge-base origin/perf/main-thread-freezes HEAD)`, not `main`.
- `LookCarryTests` is declared `nonisolated struct` so `@Test(arguments:)` can read its static under default MainActor isolation.
- Add to the report (no assertion): the time of `LookCompiler.cube(for:)` in the Simulator for an E1-only look (`LookSeeder.warmFade`) and for `LookSeeder.colourStudy`, median of 5 runs each. Above 3x the E1 time, flag it in the report; do not optimise in this task.

**Files:**
- Modify: nothing in `OpenCam/` unless a test fails; a failure means some path copies `Adjustments` key by key or tests identity without the curves, and the fix goes in that file with the smallest change, named in the report (a file outside the fence is skip-and-flag).
- Test: `OpenCamTests/LookCarryTests.swift`

**Interfaces:**
- Consumes: Tasks 3, 7, 8; E1 `LookRenderer.shared.render(_:adjustments:)`, `renderColourAndVignette(_:cube:vignette:)`, `ColourCubeCache`, `LookCompiler.cube(for:)`; E2 `LookBaker.bake(_:adjustments:renderer:)`, `LookCapture.finish(_:look:format:heicURL:dngURL:edits:renderer:)`, `CameraLook(id:name:adjustments:)`, `PhotoCaptureResult(saved:error:)`; `TestFiles.patch(_:size:)`, `TestFiles.heicData(width:height:rgb:)`, `PixelReader.rgb(_:x:y:)`, `EditFileVersion`.
- Produces: nothing new.

- [ ] **Step 1: Write the test**

```swift
// OpenCamTests/LookCarryTests.swift
@Suite struct LookCarryTests {
    func maxDiff(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float { ((a - b) * (a - b)).squareRoot().max() }
    static var curveOnly: Adjustments {
        var a = Adjustments(); a.curves.master = ToneCurve(points: [CurvePoint(x: 0, y: 0), CurvePoint(x: 0.5, y: 0.6), CurvePoint(x: 1, y: 1)]); return a }
    static let looks: [(String, Adjustments)] = [("curve", curveOnly), ("mixer", Adjustments().setting(.mixRedHue, to: 100)),
                                                 ("grading", Adjustments().setting(.gradingMidtonesSaturation, to: 100))]
    @Test(arguments: looks) func curveMixerAndGradingLooksReachTheViewfinderTheBakeAndTheRAWEdit(name: String, look: Adjustments) async throws {   // Review Focus 3
        #expect(look.hasColourChanges); #expect(!look.isIdentity); let input = SIMD3<Float>(0.75, 0.25, 0.25), expected = ColourMath.apply(look, to: input)
        #expect(maxDiff(expected, input) > 0.05, "\(name) changes the sample"); let cube = ColourCubeCache().cube(for: look); #expect(cube == LookCompiler.cube(for: look))
        let patch = try TestFiles.patch(input); let viewfinder = try PixelReader.rgb(LookRenderer.shared.renderColourAndVignette(patch, cube: cube, vignette: 0), x: 4, y: 4)
        let editor = try PixelReader.rgb(LookRenderer.shared.render(patch, adjustments: look), x: 4, y: 4)
        #expect(maxDiff(viewfinder, expected) < 0.01); #expect(maxDiff(editor, viewfinder) < 0.002)
        let baked = try LookBaker.bake(try TestFiles.heicData(width: 64, height: 64, rgb: input), adjustments: look)
        #expect(maxDiff(try PixelReader.rgb(try #require(CIImage(data: baked)), x: 32, y: 32), expected) < 0.03)
        let dir = try TestFiles.directory(), dng = dir.appending(path: "OC_0001.DNG"); try Data("dng bytes".utf8).write(to: dng)
        let camera = CameraLook(id: UUID(), name: name, adjustments: look); _ = await LookCapture.finish(PhotoCaptureResult(saved: [dng], error: nil), look: camera, format: .raw,
                                     heicURL: dir.appending(path: "OC_0001.HEIC"), dngURL: dng, edits: EditStore(directory: dir))
        #expect(try EditStore(directory: dir).load(stem: "OC_0001").adjustments == look)
        #expect(try JSONDecoder().decode(EditFileVersion.self, from: Data(contentsOf: EditStore(directory: dir).url(forStem: "OC_0001"))).version == 2)
        #expect(try JSONDecoder().decode(CameraLook.self, from: JSONEncoder().encode(camera)) == camera) } }
```

- [ ] **Step 2: Run it.** `OPENCAM_SIM_NAME="OpenCam Dev B" scripts/test.sh LookCarryTests`. Expected: `** TEST SUCCEEDED **` with no camera or render change; that is the point. Then `OPENCAM_SIM_NAME="OpenCam Dev B" scripts/test.sh` with each of `StandInLookTests`, `LookBakerTests`, `LookCaptureTests`, `FramePartsTests`: `** TEST SUCCEEDED **` four times.
- [ ] **Step 3: The viewfinder shows the study look with no camera code.** The look persists in the Simulator's Documents, so seed it through the Library, then relaunch the camera without `SHOT_FRESH`:

```bash
export SHOT_DIR=docs/screenshots/e3
OPENCAM_SIM_NAME="OpenCam Dev B" SHOT_FRESH=1 scripts/shot.sh e3-seed-study -orientation portrait -screen library -seedStudy on
OPENCAM_SIM_NAME="OpenCam Dev B" scripts/shot.sh e3-camera-study-photo-v -orientation portrait -mode photo -cameraLook "Colour study"
```

Pass when the stand-in is visibly matte, cooler in the shadows and warmer in the highlights against `docs/screenshots/e2/e2-camera-none-photo-v.png`, the summary ends with "Colour study", and "No camera in Simulator" still shows.
- [ ] **Step 4: Sweep by reading.** Each holds or is fixed: `git diff main -- OpenCam/Capture OpenCam/Capability OpenCam/App/CameraModel*.swift OpenCam/App/OpenCamApp.swift OpenCam/Render/LookRenderer.swift OpenCam/Render/LookCompiler.swift OpenCam/Render/LookBaker.swift OpenCam/UI/Theme.swift` is empty; `git diff main -- OpenCam/Render/ColourCubeCache.swift` is the `colourPart` change only; `ColourMath.apply`'s doc comment lists the ten stages in order; every string of the copy list appears verbatim and no UI string added has an em dash; no "Masks", "Crop", "Texture", "Clarity" or "Dehaze" in `OpenCam/UI`; `PhotoEdit.currentVersion == 2` and `Look.currentVersion == 2` are the only version changes.
- [ ] **Step 5: Run every suite.** `OPENCAM_SIM_NAME="OpenCam Dev B" scripts/test.sh`, expected `** TEST SUCCEEDED **`; then `xcodebuild -project OpenCam.xcodeproj -scheme OpenCam -sdk iphoneos -destination generic/platform=iOS -derivedDataPath .build CODE_SIGNING_ALLOWED=NO build`, expected `** BUILD SUCCEEDED **`.
- [ ] **Step 6: Commit** `git add OpenCamTests docs/screenshots/e3 && git commit -m "test: pin that curves, mixer and grading reach the viewfinder and capture through the one table"`

**Full E3 verification** (results in the PR with the screenshots and the tap-test notes):
- [ ] `scripts/test.sh` passes, every suite; paste the summary line. Every `e3-` screenshot exists and meets its pass line.
- [ ] Review Focus 1 to 5: the pinned tests named in the PR with their pass.
- [ ] The tap and drag tests of Tasks 1, 5, 7 and 8 done on the folded and the open simulator, each step's outcome written down; any step not done is listed as Not verified with the reason.
- [ ] By hand, folded, from a fresh install: open a photo; Curve: lift the black point and add an S; Mix: darken Blue luminance; Grading: cool the shadows; Done, reopen, all as left; "Save as look" "Test"; pick "Test" in the camera's Look row: the stand-in shows it; Reset all returns the original.
- [ ] **On the device** (Tanner): a look made with all three tools looks the same in the viewfinder, a captured HEIF and the editor; on a 48 MP photo the curve points, wheel pucks and mixer sliders keep up with the finger; the curve and wheels work with Apple Pencil; the RAW, RAW + HEIF badges and the lens line are right for real captures and real DNGs.

## Deviations ruled during the build (2026-11-11/12)

What was built differs from the text above in these places; each was a controller ruling, recorded with its reason in the PR.

- **Photo info** opens a full-height sheet with "Done", not a popover: a popover opens below the info line and the folded display leaves it about 250 pt, too little for the title and seven rows (checked by tapping). The ISO row's value is "100" (the summary keeps "ISO 100"). Shutter below 1 s prints "1/n s" only when 1/t is within 5% of a whole n ≥ 2, else one decimal ("0.8 s"). Exif facts outside sane ranges are dropped.
- **Group picker** is a sideways-scrolling row of system buttons, not a segmented control: inside a scroll view a segmented control takes every drag that starts on it, so the last groups could not be reached on the folded display. Nothing of it draws past the panel edge into the system strip.
- **Panel heights**: stacked, Curve, Mix and Grading keep 340 pt (Mix added: at 240 pt only 1.5 sliders showed).
- **Curve canvas**: about 205 pt folded portrait and 215 pt folded landscape (measured on the screenshots), not 230 and 288. The panel's own picker and Reset are 44 pt targets and the canvas takes what is left; a 355 pt Curve panel would bring portrait to about 220 pt at the cost of 15 pt of picture. At accessibility text sizes the canvas shrinks to fit (about 164 pt at XL). Points are added and removed by tap, drag off the plot and double tap, as planned.
- **Grading wheels**: one wheel at a time, not a triangle (Tanner, 2026-11-12). The triangle and its sliders needed about 470 pt in a panel of about 290, so Shadows and Highlights were whole only after a scroll. A segmented Shadows / Midtones / Highlights picker sits above the panel's scroll view and opens on Midtones (`EditorModel.gradingRegion`, not saved). The chosen range's wheel is 144 pt in every layout, not 160: at 160 the folded portrait panel cut its Luminance slider at rest. Blending and Balance follow after a scroll.
- **Table cost**: mixer and grading values are held as derived lanes in `Adjustments` (not encoded) so stages 8 and 9 read no dictionary per lattice point; stage 8 mixes and stage 9 grades the clamped colour. Debug Simulator table build: about 50 ms for an E1 look, about 140 ms for "Colour study".
- **Colour study** reads punchier rather than matte in the viewfinder: its mixer saturation boosts outweigh its black lift.

## Later work (not in this plan)

- RAW development from DNG (white balance and exposure in the RAW filter): needs DNG files from the phone to build and check against; the Simulator cannot write one.
- Masks and healing: spatial, per-region work with its own storage and UI; they cannot live in the one colour table.
- Crop and straighten: geometry, not colour; it changes export, thumbnails and the proxy, and would not show in the viewfinder.
- Texture, clarity and dehaze: spatial filters, so they cannot go in the colour table and would not show in the viewfinder; adding them breaks the "same everywhere" rule unless the viewfinder gains a spatial stage.
- A targeted mixer (drag on the photo to pick the band) and a Global wheel: easy additions once the Mix and Grading groups have been used. A 65-point table, if narrow mixer bands or steep curves band visibly on the device.

## Calls made in this plan

- **Order of tasks:** format badges and the info line first (they need nothing else), then versions, curves, histogram, the curve editor, mixer and grading maths, the mixer, the wheels, and the one-table check. Each group appears in the editor in the task that builds its UI.
- **Format designations:** from the item's files, never metadata: a DNG alone "RAW"; HEIC or HEIF "HEIF"; with a DNG of the same number "RAW + HEIF"; JPG or JPEG "JPEG"; PNG "PNG"; a JPEG with a DNG "RAW + JPEG". The titles match the camera's `PhotoFormat` titles. Badge at the tile's bottom left; clips unchanged.
- **Photo facts:** read from the editable picture's Exif (the HEIC of a pair carries the same Exif as its DNG); nothing stored; a value absent, not a number or not above 0 is left out. The line under the picture reads designation · lens · aperture · shutter · ISO, where lens is the 35 mm equivalent focal length, else the real focal length, else the lens model (Apple's lens model strings are long); the full lens model is in the "Photo info" popover. The line costs 36 pt of picture height when stacked.
- **Simulator samples:** `-seedFormats on` writes a JPG, a placeholder DNG alone, a HEIC with sample Exif and a HEIC + placeholder DNG pair. The RAW-only tile therefore shows "This photo could not be opened." with its badge in the Simulator; real RAW is checked on the device.
- **Curve storage:** per channel, 2 to 16 control points with coordinates on a 0.001 step; the end points are ordinary points that can move (black and white points, fades) but never be removed; the curve is flat outside them. `matches` compares curves exactly because the stored values are already snapped. Only non-identity channels are written to JSON.
- **Curve formula:** monotone cubic Hermite with Fritsch–Butland tangents (the draft's harmonic mean, weighted for unequal spacing). It never overshoots between two points, so points that rise give a rising curve; points may be placed to go down (an inverted or bent channel), as in Lightroom.
- **Curve channels:** "RGB" (master), "Red", "Green", "Blue"; the RGB curve runs first, then the channel's own curve, on encoded values. No luminance-only curve yet.
- **Adding and removing points:** a touch within 22 pt of a point drags it; a touch within 22 pt of the curve adds a point exactly on the curve and drags it (so a tap adds a point without changing the picture); a touch elsewhere does nothing. A point dragged more than 24 pt off the plot is removed on release, and shown faded while it would be. Double-tap a point removes it. "Reset" straightens the shown channel only. Dragging is relative to where the point was, not the finger, so a tap never jumps it. At most 16 points.
- **Histogram:** of the rendered preview (what the person sees), not the original; 256 bins of luma (Rec. 709 weights on encoded values, matching `ColourMath.luma`) and of red, green and blue, from a copy at most 256 px long; heights scale to the largest bin other than pure black and white. RGB shows all four; a colour channel shows its own. Counted in Swift on the 8-bit Display P3 preview rather than with `CIAreaHistogram`, which would count in Core Image's linear working space and need a colour-managed read-back; the preview's bytes are already the values on the curve's x axis.
- **Stage order:** E1 tones, then point curves, then vibrance and saturation, then the colour mixer, then colour grading, then clamp. Grading after saturation so a black-and-white look can be toned. Each new stage is skipped when it changes nothing, so E1 tables are bit for bit the same (pinned against a frozen copy of the E1 maths).
- **Mixer:** the draft's maths: bands at 0, 30, 60, 120, 180, 240, 270, 300 degrees with linear falloff to the next centre; hue up to ±30 degrees, saturation 0 to 2 times, luminance ±50 percent times the colour's saturation; greys never move. The band picker is a 2 x 4 grid of system buttons tinted with each band's colour, because eight segments do not fit and a segmented control cannot show colours.
- **Grading:** the draft's maths plus a luminance per region (up to ±0.2 encoded, weighted by the region) and Blending, which changes the region ramps' exponent (2 at 0, 1 at +100 for wide overlap, 4 at −100 for narrow). Blending is stored as −100...100 with 0 the default (Lightroom shows 0...100 with 50) so every value keeps "zero is no change". Hue 0 at the wheel's right, increasing clockwise; a puck dragged to the centre stores hue 0.
- **Wheel layout:** always a triangle (Midtones on top, Shadows bottom left, Highlights bottom right), diameter `min(160, (panel width − 44)/2)`: 160 pt folded portrait, 138 pt beside the picture. A row of three would leave wheels under 100 pt at these widths. Drags on a wheel move the puck and never scroll the panel; the panel scrolls from outside the wheels.
- **Panel space:** stacked (folded portrait), Curve and Grading keep a 340 pt panel instead of 240 pt, so the picture shrinks while they are chosen (to about 224 pt for a 4:3 photo). The curve canvas is about 230 pt folded portrait and 288 pt elsewhere.
- **Groups:** Light, Colour, Curve, Mix, Grading, Detail, Effects, Looks, in a sideways-scrolling system segmented picker. This moves Detail and Effects right of the new groups.
- **Version numbers:** edit files 1 → 2 (`PhotoEdit.currentVersion`); look files gain `version`, `Look.currentVersion = 2`, a missing one read as 1; both stores stamp the current version on every write. The build before this plan opens a version 2 edit read-only. It reads no version from looks, so it lists a newer look without the new tools and a rename there drops them. `CameraLook` and `SavedSelections` are not versioned (camera files, outside the fence): an older build keeps a selected look's E1 values only.
- **Launch flags:** `-seedFormats on`, `-seedStudy on`, `-editorLook <name>`, all scripted, seeded in `LibraryView.applyLaunch` so `OpenCamApp` is not touched. The camera screenshot reaches "Colour study" by seeding it through the Library first, then relaunching with `-cameraLook`.
- **Not touched:** `Theme.swift` (camera screen file): new sizes live as constants on the new views. `ColourCubeCache` changes by one line, the only Render file outside `ColourMath` that changes. The table stays at 33 points.
