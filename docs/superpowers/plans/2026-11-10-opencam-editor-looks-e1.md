# OpenCam Editor and Looks, Part E1, Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Non-destructive photo editing in OpenCam: a Library of everything in Captures, an Editor with Light, Colour, Detail and Effects sliders, looks that are made, saved, managed and applied to one or many photos, Photos import, and export of a baked full-size HEIF or JPEG.

**Architecture:** Plain `Codable` models (`Adjustments`, `Look`, `PhotoEdit`) live in JSON files beside the originals, which are never rewritten. Pure colour maths compiles every colour slider into one 33-point 3D table; one `LookRenderer` with one Metal-backed `CIContext` applies that table and the spatial filters, and serves the editor proxy, the thumbnails and the export. `@Observable` main-actor models (`LibraryStore`, `EditorModel`) drive system SwiftUI screens; all decoding and rendering runs off the main actor.

**Tech Stack:** Swift 6, SwiftUI, Core Image (`CIColorCubeWithColorSpace`, `CISharpenLuminance`, `CINoiseReduction`, `CIRandomGenerator`, `CIVignetteEffect`, `CIRAWFilter`), ImageIO, PhotosUI (`PhotosPicker`), UniformTypeIdentifiers, CryptoKit, Swift Testing, Xcode 27.2, `xcodebuild`, `simctl`.

**Spec:** `docs/superpowers/specs/2026-11-10-opencam-editor-looks-design.md`, section "Order of work", row E1. This plan is `docs/superpowers/plans/2026-11-10-opencam-editor-looks-e1.md`. Interfaces of the camera core come from `docs/superpowers/plans/2026-11-09-duocam-camera-core.md`. API facts come only from `docs/research/capture-apis.md`, `docs/research/duo-layout-apis.md`, or a grep of `$(xcrun --sdk iphoneos --show-sdk-path)`; never from memory.

## Global Constraints

Every constraint of the camera core plan applies unchanged:

- "iPhone Duo only, iOS 27.1 or later, Xcode 27.2, Swift 6, SwiftUI." Deployment target `27.1`, `SWIFT_VERSION = 6.0`, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `SWIFT_APPROACHABLE_CONCURRENCY = YES` (both already set). Targets `OpenCam` (`local.opencam.app`) and `OpenCamTests` (Swift Testing), file-system-synchronized groups, so new files need no project edits. All paths are relative to the repo root.
- "No third-party dependencies." "SwiftUI with system components and system glass throughout; dark appearance only." All four interface orientations. `Theme` (`OpenCam/UI/Theme.swift`) for spacing and accent.
- Anti-goals, verbatim from the camera core: "A control that names a format or tool the device cannot actually use at that moment." "Imitation blur or glass drawn by hand where a system material exists." From this spec: "An edit that cannot be undone back to the original file." "A look that renders differently in the viewfinder, in the saved file and in the editor. One renderer serves all three." "Sliders that lag behind the finger on a 48 MP photo." "A control for a tool that is not built yet."
- Simulator: tests and screenshots use only `OpenCam Dev` (`com.apple.CoreSimulator.SimDeviceType.iPhone-Duo`, `com.apple.CoreSimulator.SimRuntime.iOS-27-2-iPhone19-4`) by UDID through `scripts/sim-udid.sh`. Never `booted`, never another simulator.
- Code: no force unwraps, force casts or `try!` (tests included); no `Any`-typed values in our APIs; one type per file; errors are specific enums conforming to `Error, CustomStringConvertible` with messages `[Module:Function] Description — {context}`, and every `path:` in an error is `url.path(percentEncoded: false)` of the URL the caller passed; no `@preconcurrency import`, no `nonisolated(unsafe)`, no new `@unchecked Sendable`.
- Copy: plain, factual, sentence case, no em dashes in UI strings, no marketing or AI words, nothing named that is not built. Error descriptions are only logged (`Logger(subsystem: "local.opencam.app", category: <type>)`), never shown.
- Git: conventional commits, no attribution lines, never force-push.

Added by this plan:

- Folders: `OpenCam/Edit/` (models and stores), `OpenCam/Render/` (colour maths, compiler, decoder, renderer, export), `OpenCam/Library/` (library store, thumbnails, import, seeding), `OpenCam/UI/Library/`, `OpenCam/UI/Editor/`.
- Isolation: every type in `Edit/`, `Render/` and `Library/` is `nonisolated` and `Sendable`, except `LibraryStore`, `PhotoImporter` and `SampleSeeder`, which are main-actor because `CaptureStore` and `ImageRenderer` are. Only `LibraryStore`, `EditorModel` and views are `@Observable`/main-actor. Work that must leave the main actor is a `@concurrent` function (as `CapabilityScanner` does); with approachable concurrency a plain `nonisolated async` function runs on the caller's actor.
- Branch: `feat/editor-looks`, stacked on `feat/camera-core`, which holds the finished camera core (Tasks 1 to 12). Every camera core name below is as it is in that tree: `CaptureStore`, `CaptureFileKind`, `ClipSidecar`, `ClipFacts`, `CameraModel` (split into `CameraModel.swift`, `+Recording`, `+Scan`, `+Sweep`), `LibraryThumbnail`, `StripToolbar`, `CameraRootView`, `LaunchConfig`, `NoticeSource`.
- Capture files are matched by `CaptureStore.clipKey(for:)` (the file name), never by URL equality, wherever this plan compares a file it found with one it holds.
- Camera notices: E1 shows none on the camera screen. Any later one goes only through `CameraModel.show(_:from:)` / `clearNotice(from:)` with a `NoticeSource`. The Library and Editor show their own messages in their own alerts.
- Names: E1's colour maths is `ColourMath` in `OpenCam/Render/`; it is unrelated to the capture `ColourMode` in `OpenCam/Capability/` and never touches it.
- Files: looks are `Documents/Looks/<uuid>.json`; an edit is `Documents/Captures/<stem>.edit.json` (`OC_0001.edit.json`); thumbnails are `Library/Caches/Thumbnails/<key>`, where the key already ends in `.jpg`; exports go to `tmp/Export/`. Nothing in E1 writes into Captures except imports, Simulator samples and `.edit.json` files. No original is ever rewritten.
- One renderer: `LookRenderer.shared` owns the only `CIContext`. The editor preview, look tiles, thumbnails and export all pass through `LookRenderer.render(_:adjustments:)`. The colour table is applied in Display P3 (`CGColorSpace.displayP3`), because iPhone photos are P3 and an sRGB table would clip them; every rendered `CGImage`, thumbnail and exported file is Display P3. Display P3 and sRGB share one transfer curve, so `ColourMath` works on P3-encoded values unchanged. Its luma uses the Rec. 709 weights on P3-encoded values: a deliberate simplification, not a colourimetric luminance.
- Proxy rule: while editing, every render uses a proxy whose long side is at most `EditorModel.proxyLongSide = 2048` px. The full-size original is decoded only by `PhotoExporter`.
- Exact UI copy, used verbatim: slider names Exposure, Contrast, Highlights, Shadows, Whites, Blacks, Temperature, Tint, Vibrance, Saturation, Sharpening, Noise reduction, Grain, Vignette; groups Light, Colour, Detail, Effects, Looks; "This photo could not be opened."; "The photo could not be exported."; "The edit could not be saved."; "The items could not be deleted."; "This video could not be opened."; "No photos yet" / "Take one or import from Photos."; "This photo was edited by a newer version of OpenCam."; "No photos were changed."; "Enter a name."; "Use 40 characters or fewer."; buttons "Done", "Reset all", "Export", "Import", "Select", "Apply look", "Remove look", "None", "Save as look", "Rename", "Duplicate", "Delete", "Cancel", "Save", "OK", "Original".
- Screenshots: `SHOT_DIR=docs/screenshots/e1`, names prefixed `e1-`, taken on display 1 (the outer display) by `scripts/shot.sh`, which Task 5 extends. The implementer reads every PNG.
- Edit files from a newer build (Task 1, as built): `EditStore` loads them, but `save` and `remove` throw `EditStoreError.newerVersion(path:version:)` and leave the file unchanged. Every later path that saves or removes an edit (editor Done, Apply look, Remove look, Delete) catches that case, logs it and shows `LibraryCopy.newerEdit` ("This photo was edited by a newer version of OpenCam."), never an error description; Apply look and Remove look count such photos as skipped. Task 1 also defines `LookStoreError.unreadable(path:reason:)` for look read and decode failures; later tasks use it rather than adding another case. An `.edit.json` counts toward `CaptureStore`'s next number (numbers only skip ahead), so a library item is never deleted without its edit file.
- Calls made in this plan (deviations from the brief, each small): (1) The editor also uses the side-by-side layout when the vertical size class is compact, because a picture above a panel does not fit the outer display's 466 pt landscape height; regular width still means side by side. This is a deliberate addition to the spec's "Folded (outer display): photo above the panel", which then holds for portrait only; it is recorded in the spec's calls made without Tanner. (2) The empty state is a `ContentUnavailableView` titled "No photos yet" with the description "Take one or import from Photos.". (3) Import keeps the original bytes and accepts HEIC, HEIF, JPEG, PNG and DNG; any other type, and anything that does not decode, fails with the plain message. (4) "Remove look" and the Looks group's "None" clear the whole edit of a photo that has a look (a look is copied in, so its values cannot be separated from later changes); photos without a look are untouched. (5) Simulator samples are JPEG, so the samples do not depend on HEVC encoding in the Simulator. (6) One extra scripted flag, `-librarySelect on`, opens Library in Select mode with the newest photo selected, so Select mode can be screenshotted. (7) The Library item keeps Task 11's last-capture image (now counting JPG and PNG too); tapping it opens Library instead of Quick Look. Library lists clips too, and a clip opens in the system preview, so videos stay reachable in the app. (8) The share sheet is a `UIActivityViewController` in a `UIViewControllerRepresentable`, because the file exists only after the render.

## Review Focus

1. An edit file written by a newer version with unknown keys must still load, keeping every value it understands. Pinned by `EditStoreTests.newerEditFileWithUnknownKeysLoads` (Task 1).
2. A 48 MP original must never be rendered at full size during slider movement. Pinned by `EditorModelTests.fortyEightMegapixelOriginalRendersOnlyTheProxy` (Task 7).
3. Deleting a look must not change photos that already used it. Pinned by `LibraryLookTests.deletingALookKeepsPhotosThatUsedIt` (Task 8).
4. Importing a photo whose format the device cannot decode must fail with the plain message and leave nothing half-written in Captures. Pinned by `PhotoImporterTests.undecodableImportFailsAndLeavesCapturesUntouched` (Task 6).
5. An original that disappears from disk while its editor is open must not crash and must say the photo could not be opened. Pinned by `EditorModelTests.originalRemovedWhileOpenSaysCannotOpen` (Task 7) and `PhotoExporterTests.missingSourceThrows` (Task 9).

---

### Task 1: Adjustments, looks, edits and their stores

**Files:**
- Create in `OpenCam/Edit/`: `Adjustments.swift`, `AdjustmentKey.swift`, `EditorGroup.swift`, `Look.swift`, `LookStore.swift`, `LookStoreError.swift`, `PhotoEdit.swift`, `EditStore.swift`, `EditStoreError.swift`
- Test: `OpenCamTests/AdjustmentsTests.swift`, `OpenCamTests/LookStoreTests.swift`, `OpenCamTests/EditStoreTests.swift`, `OpenCamTests/TestFiles.swift` (`enum TestFiles { static func directory() throws -> URL }`, a new empty folder under `FileManager.default.temporaryDirectory`; later tasks add to it)

**Interfaces:**
- Consumes: nothing.
- Produces (all `nonisolated`):

```swift
struct Adjustments: Codable, Sendable, Hashable {   // JSON keys are the property names
    var exposure = 0.0, contrast = 0.0, highlights = 0.0, shadows = 0.0, whites = 0.0, blacks = 0.0, temperature = 0.0, tint = 0.0
    var vibrance = 0.0, saturation = 0.0, sharpening = 0.0, noiseReduction = 0.0, grain = 0.0, vignette = 0.0
    init(); init(from decoder: any Decoder) throws   // every key optional (missing = 0), unknown keys ignored, each value clamped to its key's range
    subscript(key: AdjustmentKey) -> Double { get set }               // set clamps to key.range
    func setting(_ key: AdjustmentKey, to value: Double) -> Adjustments
    var isIdentity: Bool { get }                  // all fourteen values are 0
    var hasColourChanges: Bool { get }            // any of exposure...saturation is not 0
}
enum AdjustmentKey: String, CaseIterable, Sendable {
    case exposure, contrast, highlights, shadows, whites, blacks, temperature, tint, vibrance, saturation, sharpening, noiseReduction, grain, vignette
    var title: String { get }                     // "Exposure" ... "Noise reduction" ... "Vignette"
    var range: ClosedRange<Double> { get }        // exposure -5...5; sharpening, noiseReduction, grain 0...100; others -100...100
    var step: Double { get }                      // exposure 0.1, others 1
    var group: EditorGroup { get }
    func valueText(_ value: Double) -> String     // exposure "+0.5" "0.0" "-1.3"; signed ranges "+20" "0" "-35"; 0...100 ranges "20"
}
enum EditorGroup: String, CaseIterable, Sendable {
    case light, colour, detail, effects, looks    // raw values are the -editorGroup values
    var title: String { get }                     // "Light", "Colour", "Detail", "Effects", "Looks"
    var keys: [AdjustmentKey] { get }             // looks: []
}
struct Look: Codable, Sendable, Equatable, Identifiable { let id: UUID; var name: String; var adjustments: Adjustments; let createdAt: Date }
struct LookStore: Sendable {
    static let maxNameLength = 40
    static func appDefault() throws(LookStoreError) -> LookStore   // Documents/Looks
    init(directory: URL) throws(LookStoreError)                     // creates the folder
    let directory: URL
    func all() -> [Look]          // name by localizedStandardCompare, then createdAt; unreadable files skipped and logged
    func save(name: String, adjustments: Adjustments, now: Date = .now) throws(LookStoreError) -> Look
    func rename(_ id: UUID, to name: String) throws(LookStoreError) -> Look
    func duplicate(_ id: UUID, now: Date = .now) throws(LookStoreError) -> Look   // "<name> copy", base cut so the result is <= 40
    func delete(_ id: UUID) throws(LookStoreError)
    static func validName(_ raw: String) throws(LookStoreError) -> String         // trimmed of whitespace and newlines
    static func nameProblem(_ raw: String) -> String?                             // "Enter a name." / "Use 40 characters or fewer." / nil
}
enum LookStoreError: Error, CustomStringConvertible, Equatable { case emptyName, nameTooLong(count: Int), notFound(id: UUID), unwritable(path: String, reason: String), directoryUnavailable(reason: String) }
struct PhotoEdit: Codable, Sendable, Equatable {
    static let currentVersion = 1
    var adjustments = Adjustments(); var lookName: String? = nil; var version = PhotoEdit.currentVersion
    init(adjustments: Adjustments = Adjustments(), lookName: String? = nil)
    init(from decoder: any Decoder) throws        // missing adjustments = identity, missing version = 1, unknown keys ignored
    var isIdentity: Bool { get }                  // adjustments.isIdentity && lookName == nil
}
struct EditStore: Sendable {
    init(directory: URL)                          // the Captures folder
    static func fileName(forStem stem: String) -> String          // "OC_0001.edit.json"
    func url(forStem stem: String) -> URL
    func load(stem: String) throws(EditStoreError) -> PhotoEdit   // PhotoEdit() when the file is missing
    func save(_ edit: PhotoEdit, stem: String) throws(EditStoreError)   // atomic write; an identity edit removes the file instead
    func remove(stem: String) throws(EditStoreError)              // a missing file is not an error
}
enum EditStoreError: Error, CustomStringConvertible { case unreadable(path: String, reason: String), unwritable(path: String, reason: String) }
```

Look files are written with `JSONEncoder` (`.prettyPrinted, .sortedKeys`, ISO 8601 dates) and `.atomic`. A look file is named by its `id`, so duplicate names never collide.

- [ ] **Step 1: Write the failing tests**

```swift
@Suite struct AdjustmentsTests {
    @Test func defaultsAreIdentityAndRoundTrip() throws {
        #expect(Adjustments().isIdentity); #expect(!Adjustments().hasColourChanges)
        let a = Adjustments().setting(.exposure, to: 1.5).setting(.grain, to: 30).setting(.tint, to: -12)
        #expect(!a.isIdentity); #expect(a.hasColourChanges); #expect(!Adjustments().setting(.grain, to: 30).hasColourChanges)
        #expect(try JSONDecoder().decode(Adjustments.self, from: JSONEncoder().encode(a)) == a)
    }
    @Test func decodingToleratesMissingAndUnknownKeysAndClamps() throws {
        let json = #"{"exposure": 9, "contrast": -250, "saturation": 40, "toneCurve": [0, 1]}"#
        let a = try JSONDecoder().decode(Adjustments.self, from: Data(json.utf8))
        #expect(a.exposure == 5); #expect(a.contrast == -100); #expect(a.saturation == 40); #expect(a.shadows == 0); #expect(a.grain == 0)
    }
    @Test func keysCarryTitlesRangesGroupsAndText() {
        #expect(AdjustmentKey.allCases.map(\.title) == ["Exposure", "Contrast", "Highlights", "Shadows", "Whites", "Blacks", "Temperature", "Tint",
                                                         "Vibrance", "Saturation", "Sharpening", "Noise reduction", "Grain", "Vignette"])
        #expect(AdjustmentKey.exposure.range == -5...5); #expect(AdjustmentKey.grain.range == 0...100); #expect(AdjustmentKey.vignette.range == -100...100)
        #expect(EditorGroup.light.keys == [.exposure, .contrast, .highlights, .shadows, .whites, .blacks])
        #expect(EditorGroup.colour.keys == [.temperature, .tint, .vibrance, .saturation])
        #expect(EditorGroup.detail.keys == [.sharpening, .noiseReduction]); #expect(EditorGroup.effects.keys == [.grain, .vignette])
        #expect(EditorGroup.looks.keys.isEmpty); #expect(EditorGroup.allCases.map(\.title) == ["Light", "Colour", "Detail", "Effects", "Looks"])
        #expect(AdjustmentKey.exposure.valueText(0.5) == "+0.5"); #expect(AdjustmentKey.exposure.valueText(0) == "0.0")
        #expect(AdjustmentKey.contrast.valueText(-35) == "-35"); #expect(AdjustmentKey.contrast.valueText(20) == "+20"); #expect(AdjustmentKey.grain.valueText(20) == "20")
        #expect(Adjustments().setting(.exposure, to: 8).exposure == 5)
    }
}

@Suite struct EditStoreTests {
    @Test func newerEditFileWithUnknownKeysLoads() throws {   // Review Focus 1
        let dir = try TestFiles.directory()
        let json = #"{"version": 3, "lookName": "Warm fade", "adjustments": {"exposure": 1, "toneCurve": [[0, 0], [1, 1]]}, "masks": [{"kind": "sky"}], "crop": {"angle": 2}}"#
        try Data(json.utf8).write(to: dir.appending(path: "OC_0001.edit.json"))
        let edit = try EditStore(directory: dir).load(stem: "OC_0001")
        #expect(edit.adjustments == Adjustments().setting(.exposure, to: 1)); #expect(edit.lookName == "Warm fade"); #expect(edit.version == 3)
    }
    @Test func roundTripAndMissingFile() throws {
        let store = EditStore(directory: try TestFiles.directory())
        #expect(try store.load(stem: "OC_0002") == PhotoEdit())
        let edit = PhotoEdit(adjustments: Adjustments().setting(.shadows, to: 30), lookName: "Warm fade")
        try store.save(edit, stem: "OC_0002")
        #expect(try store.load(stem: "OC_0002") == edit); #expect(EditStore.fileName(forStem: "OC_0002") == "OC_0002.edit.json")
    }
    @Test func identityEditWithoutLookRemovesTheFile() throws {
        let store = EditStore(directory: try TestFiles.directory())
        let path = store.url(forStem: "OC_0003").path(percentEncoded: false)
        try store.save(PhotoEdit(adjustments: Adjustments().setting(.tint, to: 5)), stem: "OC_0003"); #expect(FileManager.default.fileExists(atPath: path))
        try store.save(PhotoEdit(), stem: "OC_0003"); #expect(!FileManager.default.fileExists(atPath: path))
        try store.save(PhotoEdit(lookName: "Plain"), stem: "OC_0003"); #expect(FileManager.default.fileExists(atPath: path))
        try store.remove(stem: "OC_0003"); try store.remove(stem: "OC_0003")
        #expect(!FileManager.default.fileExists(atPath: path))
    }
    @Test func unreadableEditThrows() throws {
        let dir = try TestFiles.directory()
        try Data("{".utf8).write(to: dir.appending(path: "OC_0004.edit.json"))
        #expect(throws: EditStoreError.self) { try EditStore(directory: dir).load(stem: "OC_0004") }
    }
}

@Suite struct LookStoreTests {
    let warm = Adjustments().setting(.temperature, to: 20)
    let forty = String(repeating: "b", count: 40), thirtyFiveCopy = String(repeating: "b", count: 35) + " copy"
    @Test func saveListsSortedByNameAndAllowsDuplicates() throws {
        let store = try LookStore(directory: TestFiles.directory())
        _ = try store.save(name: "  warm fade ", adjustments: warm)
        _ = try store.save(name: "Agfa", adjustments: Adjustments()); _ = try store.save(name: "Agfa", adjustments: warm)
        #expect(store.all().map(\.name) == ["Agfa", "Agfa", "warm fade"]); #expect(store.all().last?.adjustments == warm)
        let saved = try #require(store.all().last)
        #expect(FileManager.default.fileExists(atPath: store.directory.appending(path: "\(saved.id.uuidString).json").path(percentEncoded: false)))
    }
    @Test func nameRules() throws {
        #expect(throws: LookStoreError.emptyName) { try LookStore.validName(" \n ") }
        #expect(throws: LookStoreError.nameTooLong(count: 41)) { try LookStore.validName(forty + "b") }
        #expect(try LookStore.validName(" " + forty + " ") == forty)
        #expect(LookStore.nameProblem(" ") == "Enter a name."); #expect(LookStore.nameProblem(forty + "b") == "Use 40 characters or fewer.")
        #expect(LookStore.nameProblem("Warm fade") == nil)
    }
    @Test func renameDuplicateDelete() throws {
        let store = try LookStore(directory: TestFiles.directory())
        let look = try store.save(name: "Warm fade", adjustments: warm)
        let renamed = try store.rename(look.id, to: "Warm"); #expect(renamed.id == look.id); #expect(renamed.adjustments == warm)
        let copy = try store.duplicate(look.id); #expect(copy.name == "Warm copy"); #expect(copy.id != look.id); #expect(copy.adjustments == warm)
        let long = try store.save(name: forty, adjustments: warm); #expect(try store.duplicate(long.id).name == thirtyFiveCopy)
        try Data("{".utf8).write(to: store.directory.appending(path: "\(UUID().uuidString).json"))   // unreadable files are skipped
        try store.delete(look.id)
        #expect(Set(store.all().map(\.name)) == [thirtyFiveCopy, forty, "Warm copy"]); #expect(store.all().last?.name == "Warm copy")
        #expect(throws: LookStoreError.notFound(id: look.id)) { try store.rename(look.id, to: "X") }
    }
}
```

- [ ] **Step 2: Run to see them fail** — `scripts/test.sh AdjustmentsTests`. Expected: build error `cannot find 'Adjustments' in scope`.
- [ ] **Step 3: Implement the types in Interfaces.**
- [ ] **Step 4: Run to see them pass** — `scripts/test.sh AdjustmentsTests && scripts/test.sh EditStoreTests && scripts/test.sh LookStoreTests`. Expected: `** TEST SUCCEEDED **` three times.
- [ ] **Step 5: Commit**

```bash
git add OpenCam/Edit OpenCamTests
git commit -m "feat: add adjustments, looks and photo edits with their stores"
```

---

### Task 2: Colour maths and the look compiler

**Files:**
- Create in `OpenCam/Render/`: `ColourMath.swift`, `ColourCube.swift`, `LookCompiler.swift`
- Test: `OpenCamTests/ColourMathTests.swift`, `OpenCamTests/LookCompilerTests.swift`, `OpenCamTests/Probe.swift` (the `Probe` argument type alone, declared `nonisolated` so its `CustomTestStringConvertible` conformance is not main-actor-isolated under the test target's MainActor default)

**Interfaces:**
- Consumes: Task 1 `Adjustments`, `AdjustmentKey`.
- Produces (all `nonisolated`):

```swift
enum ColourMath {
    static func apply(_ adjustments: Adjustments, to rgb: SIMD3<Float>) -> SIMD3<Float>   // Display P3-encoded in and out, 0...1
    static func decode(_ c: Float) -> Float       // the sRGB / Display P3 transfer curve, encoded to linear
    static func encode(_ l: Float) -> Float       // linear to encoded, clamping to 0...1 first
    static func luma(_ rgb: SIMD3<Float>) -> Float
}
struct ColourCube: Sendable, Equatable {
    static let standardDimension = 33
    let dimension: Int
    let data: [Float]                             // RGBA, alpha 1; red fastest, then green, then blue
    var cubeData: Data { get }                    // the Float bytes, for CIColorCubeWithColorSpace.cubeData
}
enum LookCompiler {
    static func cube(for adjustments: Adjustments) -> ColourCube         // ColourMath.apply at every lattice point, dimension 33
    static func lattice(dimension: Int) -> ColourCube                    // the identity table
}
```

Lattice point `(r, g, b)` has value `(r, g, b) / (dimension - 1)` and starts at `((b * dimension + g) * dimension + r) * 4`. That order is from the SDK's `CIColorCube` doc comment: "The columns and rows of the data are indexed by red and green, respectively. Each data plane is followed by the next higher plane in the data, with planes indexed by blue."

The colour stage, in this fixed order, all in `Float`. `t(x) = x / 100` for every slider except exposure; `clamp01(x) = min(max(x, 0), 1)`.

```swift
decode(c) = c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
encode(l) = { let x = clamp01(l); return x <= 0.0031308 ? 12.92 * x : 1.055 * pow(x, 1 / 2.4) - 0.055 }
luma(rgb) = 0.2126 * r + 0.7152 * g + 0.0722 * b                       // Rec. 709 weights on P3-encoded values, a deliberate simplification

1. linear:        l = decode(c) per channel
2. exposure:      l *= pow(2, exposure)
3. white balance: r *= 1 + 0.3 * t(temperature);  g *= 1 - 0.3 * t(tint);  b *= 1 - 0.3 * t(temperature)
4. encode:        x = encode(l) per channel
5. contrast:      x = clamp01(0.5 + (x - 0.5) * (1 + t(contrast)))
6. tone, per channel, in this order:
   highlights:    x += t(highlights) * x * x * (1 - x)
   shadows:       x += t(shadows) * x * (1 - x) * (1 - x)
   whites:        x = clamp01(x + 0.25 * t(whites) * x * x)
   blacks:        x = clamp01(x + 0.25 * t(blacks) * (1 - x) * (1 - x))
7. vibrance:      y = luma(rgb); s = max(r, g, b) - min(r, g, b); rgb = y + (rgb - y) * (1 + t(vibrance) * (1 - s))
8. saturation:    y = luma(rgb); rgb = y + (rgb - y) * (1 + t(saturation))
9. clamp01 per channel
```

Highlights and shadows weights are 0 at 0 and 1, so black and white stay put; both curves stay inside 0...1 for t in -1...1.

- [ ] **Step 1: Write the failing tests**

```swift
// OpenCamTests/Probe.swift
nonisolated struct Probe: Sendable, CustomTestStringConvertible {
    let key: AdjustmentKey; let rgb: SIMD3<Float>; let channel: Int; let rises: Bool
    var testDescription: String { "\(key) channel \(channel)" }
}

// OpenCamTests/ColourMathTests.swift
@Suite struct ColourMathTests {
    let grey = SIMD3<Float>(repeating: 0.5)
    func apply(_ key: AdjustmentKey, _ value: Double, _ rgb: SIMD3<Float>) -> SIMD3<Float> { ColourMath.apply(Adjustments().setting(key, to: value), to: rgb) }
    func maxDiff(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float { ((a - b) * (a - b)).squareRoot().max() }

    @Test func zeroAdjustmentsReturnTheInput() {
        for rgb in [SIMD3<Float>(0, 0, 0), SIMD3(1, 1, 1), SIMD3(0.2, 0.5, 0.8), SIMD3(0.03, 0.9, 0.4)] {
            #expect(maxDiff(ColourMath.apply(Adjustments(), to: rgb), rgb) < 1e-5)
        }
    }
    @Test func plusOneStopDoublesLinearMidGrey() {
        let out = apply(.exposure, 1, grey)
        #expect(abs(ColourMath.decode(out.x) - 2 * ColourMath.decode(0.5)) < 1e-4); #expect(abs(out.x - 0.68584) < 1e-4)
    }
    @Test func saturationMinus100GivesRec709Luma() {
        let out = apply(.saturation, -100, SIMD3(0.8, 0.4, 0.2))
        #expect(abs(out.x - 0.4706) < 1e-4); #expect(abs(out.x - out.y) < 1e-6); #expect(abs(out.y - out.z) < 1e-6)
    }
    @Test func positiveTemperatureRaisesRedAndLowersBlue() {
        let out = apply(.temperature, 50, grey)
        #expect(out.x > 0.51); #expect(out.z < 0.49); #expect(abs(out.y - 0.5) < 1e-5)
    }
    @Test func highlightsAndShadowsKeepBlackAndWhite() {
        for key in [AdjustmentKey.highlights, .shadows] {
            for value in [-100.0, 100] {
                #expect(maxDiff(apply(key, value, .zero), .zero) < 1e-6); #expect(maxDiff(apply(key, value, .one), .one) < 1e-5)
            }
        }
    }
    @Test(arguments: [
        Probe(key: .exposure, rgb: SIMD3(repeating: 0.4), channel: 0, rises: true), Probe(key: .contrast, rgb: SIMD3(repeating: 0.75), channel: 0, rises: true),
        Probe(key: .highlights, rgb: SIMD3(repeating: 0.8), channel: 0, rises: true), Probe(key: .shadows, rgb: SIMD3(repeating: 0.2), channel: 0, rises: true),
        Probe(key: .whites, rgb: SIMD3(repeating: 0.8), channel: 0, rises: true), Probe(key: .blacks, rgb: SIMD3(repeating: 0.1), channel: 0, rises: true),
        Probe(key: .temperature, rgb: SIMD3(repeating: 0.5), channel: 0, rises: true), Probe(key: .temperature, rgb: SIMD3(repeating: 0.5), channel: 2, rises: false),
        Probe(key: .tint, rgb: SIMD3(repeating: 0.5), channel: 1, rises: false), Probe(key: .vibrance, rgb: SIMD3(0.7, 0.5, 0.4), channel: 0, rises: true),
        Probe(key: .saturation, rgb: SIMD3(0.7, 0.5, 0.4), channel: 0, rises: true),
    ])
    func everySliderIsMonotonic(_ probe: Probe) throws {
        let range = probe.key.range
        let values = stride(from: range.lowerBound, through: range.upperBound, by: (range.upperBound - range.lowerBound) / 40)
            .map { apply(probe.key, $0, probe.rgb)[probe.channel] }
        for (a, b) in zip(values, values.dropFirst()) { #expect(probe.rises ? b >= a - 1e-6 : b <= a + 1e-6) }
        let first = try #require(values.first), last = try #require(values.last)
        #expect(abs(last - first) > 0.05)   // the slider does something
    }
}

@Suite struct LookCompilerTests {
    func index(_ r: Int, _ g: Int, _ b: Int) -> Int { ((b * 33 + g) * 33 + r) * 4 }
    @Test func identityCubeEqualsTheLattice() {
        let cube = LookCompiler.cube(for: Adjustments()), lattice = LookCompiler.lattice(dimension: 33)
        #expect(cube.dimension == 33); #expect(cube.data.count == 33 * 33 * 33 * 4); #expect(cube.cubeData.count == 33 * 33 * 33 * 4 * 4)
        #expect(zip(cube.data, lattice.data).allSatisfy { abs($0 - $1) < 1e-5 })
    }
    @Test func latticeOrderIsRedThenGreenThenBlue() {
        let l = LookCompiler.lattice(dimension: 33).data
        #expect(l[index(1, 0, 0)] == 1 / 32); #expect(l[index(1, 0, 0) + 1] == 0)
        #expect(l[index(0, 1, 0) + 1] == 1 / 32); #expect(l[index(0, 0, 1) + 2] == 1 / 32); #expect(l[index(32, 32, 32) + 3] == 1)
    }
    @Test func plusOneStopSpotValues() {
        let a = Adjustments().setting(.exposure, to: 1), d = LookCompiler.cube(for: a).data, mid = index(16, 16, 16)
        for c in 0..<3 { #expect(abs(d[mid + c] - 0.68584) < 1e-4) }
        #expect(d[mid + 3] == 1)
        #expect(abs(d[index(8, 20, 30) + 1] - ColourMath.apply(a, to: SIMD3(8, 20, 30) / 32).y) < 1e-6)
    }
}
```

- [ ] **Step 2: Run to see them fail** — `scripts/test.sh ColourMathTests`. Expected: `cannot find 'ColourMath' in scope`.
- [ ] **Step 3: Implement `ColourMath` with exactly the formulas above, then `ColourCube` and `LookCompiler`.**
- [ ] **Step 4: Run to see them pass** — `scripts/test.sh ColourMathTests && scripts/test.sh LookCompilerTests`. Expected: `** TEST SUCCEEDED **` twice.
- [ ] **Step 5: Commit**

```bash
git add OpenCam/Render OpenCamTests
git commit -m "feat: add colour maths and compile adjustments into a colour table"
```

---

### Task 3: Picture decoding and the renderer

**Files:**
- Create in `OpenCam/Render/`: `LookRenderer.swift`, `PictureDecoder.swift`, `PictureError.swift`
- Modify: `OpenCam/App/OpenCamApp.swift` (a `.task { await LookRenderer.warmUp() }`)
- Test: `OpenCamTests/LookRendererTests.swift`, `OpenCamTests/PictureDecoderTests.swift`, `OpenCamTests/PixelReader.swift`; Modify `OpenCamTests/TestFiles.swift`

**Interfaces:**
- Consumes: Task 1 `Adjustments`; Task 2 `LookCompiler`, `ColourCube`.
- Produces (all `nonisolated`):

```swift
final class LookRenderer: Sendable {
    static let shared: LookRenderer
    let context: CIContext                        // CIContext(mtlDevice:) from MTLCreateSystemDefaultDevice(), else CIContext(); default working space
    let displayP3: CGColorSpace                   // CGColorSpace(name: CGColorSpace.displayP3), else CGColorSpaceCreateDeviceRGB()
    @concurrent static func warmUp() async        // touches `shared` so the context is created off the main actor
    func render(_ image: CIImage, adjustments: Adjustments) -> CIImage          // full pipeline; result extent == image.extent
    func renderColourAndVignette(_ image: CIImage, cube: ColourCube, vignette: Double) -> CIImage   // for E2's viewfinder
    func applyCube(_ image: CIImage, cube: ColourCube) -> CIImage               // CIColorCubeWithColorSpace, colorSpace displayP3, extrapolate false
    @concurrent func cgImage(_ image: CIImage) async -> CGImage?               // createCGImage over image.extent, displayP3, 8-bit
    @concurrent func renderedCGImage(_ image: CIImage, adjustments: Adjustments) async -> CGImage?   // render then cgImage, all off the main actor
}
enum PictureDecoder {
    static func full(at url: URL) throws(PictureError) -> CIImage    // CIImage(contentsOf:options: [.applyOrientationProperty: true]); a DNG gets the system's default RAW decode
    @concurrent static func proxy(at url: URL, longSide: Int) async throws(PictureError) -> CIImage   // long side <= longSide, never upscaled, upright
    static func pixelSize(at url: URL) throws(PictureError) -> CGSize                                // upright size from CGImageSource properties
}
enum PictureError: Error, CustomStringConvertible, Equatable { case missing(path: String), undecodable(path: String) }
// OpenCamTests: enum PixelReader { static func rgb(_ image: CIImage, x: Int, y: Int) throws -> SIMD3<Float> }   // renders one pixel as RGBAf in Display P3 through LookRenderer.shared.context
// OpenCamTests: extension TestFiles { static func patch(_ rgb: SIMD3<Float>, size: Int = 8) throws -> CIImage   // CIImage(color:) in Display P3, cropped to size x size at the origin; every TestFiles writer encodes Display P3
//     static func writeJPEG(width: Int, height: Int, rgb: SIMD3<Float>, to url: URL) throws -> URL; static func writeHEIC(width: Int, height: Int, rgb: SIMD3<Float>, to url: URL) throws -> URL
//     static func jpegData(width: Int, height: Int, rgb: SIMD3<Float>) throws -> Data; static func pngData(...) throws -> Data; static func tiffData(...) throws -> Data }
```

`render` order and values (`hasColourChanges == false` skips the cube; each spatial step is skipped when its value is 0; `scale = max(1, longSide / 2048)` keeps proxy and export alike):
- colour: `applyCube(image, cube: LookCompiler.cube(for:))`.
- sharpening `s`: `CISharpenLuminance` sharpness `0.8 * s / 100`, radius `1.5 * scale`.
- noise reduction `n`: `CINoiseReduction` noiseLevel `0.04 * n / 100`, sharpness `0.4`.
- grain `g`: `CIRandomGenerator` through `CIColorMatrix` (r, g and b vectors `(a, 0, 0, 0)`, bias `-a / 2` each, alpha vector `(0, 0, 0, 0)`, `a = 0.12 * g / 100`), scaled by `scale` with nearest sampling, cropped to the extent, added with `CIAdditionCompositing`.
- vignette `v`: `CIVignetteEffect` centre the extent's middle, radius `0.75 * hypot(w, h) / 2`, falloff `0.5`, intensity `-v / 100` (negative darkens the corners, positive lightens them).
- result cropped to `image.extent`.

`proxy`: HEIC, HEIF, JPEG and PNG use `CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceCreateThumbnailFromImageAlways`, `kCGImageSourceCreateThumbnailWithTransform` and `kCGImageSourceThumbnailMaxPixelSize = longSide`; a DNG uses `CIRAWFilter(imageURL:)` with `scaleFactor = min(1, longSide / max(nativeSize))`. The result is rendered once to a `CGImage` and returned as `CIImage(cgImage:)`, so slider renders never decode again. A missing file throws `.missing`; anything else that fails throws `.undecodable`.

- [ ] **Step 1: Write the failing tests**

```swift
@Suite struct LookRendererTests {
    let renderer = LookRenderer.shared
    func diff(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float { ((a - b) * (a - b)).squareRoot().max() }

    @Test func identityCubeKeepsPixelsSoTheDataOrderIsRight() throws {
        let input = SIMD3<Float>(0.2, 0.5, 0.8)
        let out = renderer.applyCube(try TestFiles.patch(input), cube: LookCompiler.lattice(dimension: 33))
        #expect(diff(try PixelReader.rgb(out, x: 4, y: 4), input) < 2e-3)
    }
    @Test func displayP3RedSurvivesTheColourTable() throws {   // an sRGB table would clip it to about (0.92, 0.20, 0.14)
        let red = SIMD3<Float>(1, 0, 0)
        #expect(diff(try PixelReader.rgb(renderer.applyCube(try TestFiles.patch(red), cube: LookCompiler.lattice(dimension: 33)), x: 4, y: 4), red) < 2e-3)
    }
    @Test func identityAdjustmentsReturnTheSamePixels() throws {
        for input in [SIMD3<Float>(0.2, 0.5, 0.8), SIMD3(1, 0, 0), SIMD3(0.5, 0.5, 0.5)] {
            #expect(diff(try PixelReader.rgb(renderer.render(TestFiles.patch(input), adjustments: Adjustments()), x: 4, y: 4), input) < 2e-3)
        }
    }
    @Test func plusOneStopOnMidGreyMatchesColourMath() throws {
        let a = Adjustments().setting(.exposure, to: 1)
        let out = try PixelReader.rgb(renderer.render(TestFiles.patch(SIMD3(repeating: 0.5)), adjustments: a), x: 4, y: 4)
        #expect(diff(out, ColourMath.apply(a, to: SIMD3(repeating: 0.5))) < 3e-3)
    }
    @Test func saturationMinus100GivesEqualChannels() throws {
        let out = try PixelReader.rgb(renderer.render(TestFiles.patch(SIMD3(0.8, 0.4, 0.2)), adjustments: Adjustments().setting(.saturation, to: -100)), x: 4, y: 4)
        #expect(abs(out.x - out.y) < 2e-3); #expect(abs(out.y - out.z) < 2e-3); #expect(abs(out.x - 0.4706) < 3e-3)
    }
    @Test func vignetteChangesCornersNotTheCentre() throws {
        let grey = try TestFiles.patch(SIMD3(repeating: 0.5), size: 256)
        let dark = renderer.render(grey, adjustments: Adjustments().setting(.vignette, to: -100))
        let light = renderer.render(grey, adjustments: Adjustments().setting(.vignette, to: 100))
        #expect(try PixelReader.rgb(dark, x: 1, y: 1).x < 0.4); #expect(try PixelReader.rgb(light, x: 1, y: 1).x > 0.6)
        #expect(abs(try PixelReader.rgb(dark, x: 128, y: 128).x - 0.5) < 0.02)
    }
    @Test func spatialStepsKeepTheExtentAndViewfinderPathMatches() throws {
        let image = try TestFiles.patch(SIMD3(0.6, 0.4, 0.3), size: 64)
        let all = Adjustments().setting(.sharpening, to: 50).setting(.noiseReduction, to: 50).setting(.grain, to: 50).setting(.vignette, to: -30)
        #expect(renderer.render(image, adjustments: all).extent == image.extent)
        let colour = Adjustments().setting(.temperature, to: 40).setting(.vignette, to: -30)
        let full = try PixelReader.rgb(renderer.render(image, adjustments: colour), x: 10, y: 10)
        let viewfinder = try PixelReader.rgb(renderer.renderColourAndVignette(image, cube: LookCompiler.cube(for: colour), vignette: -30), x: 10, y: 10)
        #expect(diff(full, viewfinder) < 1e-3)
    }
}

@Suite struct PictureDecoderTests {
    @Test func proxyIsCappedAndNeverUpscaled() async throws {
        let dir = try TestFiles.directory()
        let wide = try TestFiles.writeJPEG(width: 3000, height: 1500, rgb: SIMD3(0.5, 0.5, 0.5), to: dir.appending(path: "wide.JPG"))
        let small = try TestFiles.writeJPEG(width: 100, height: 50, rgb: SIMD3(0.5, 0.5, 0.5), to: dir.appending(path: "small.JPG"))
        #expect(try await PictureDecoder.proxy(at: wide, longSide: 2048).extent.size == CGSize(width: 2048, height: 1024))
        #expect(try await PictureDecoder.proxy(at: small, longSide: 2048).extent.size == CGSize(width: 100, height: 50))
        #expect(try PictureDecoder.pixelSize(at: wide) == CGSize(width: 3000, height: 1500))
    }
    @Test func missingAndUndecodableFilesThrow() async throws {
        let dir = try TestFiles.directory(), junk = dir.appending(path: "junk.JPG"), gone = dir.appending(path: "gone.JPG")
        try Data("not a picture".utf8).write(to: junk)
        await #expect(throws: PictureError.undecodable(path: junk.path(percentEncoded: false))) { try await PictureDecoder.proxy(at: junk, longSide: 360) }
        await #expect(throws: PictureError.missing(path: gone.path(percentEncoded: false))) { try await PictureDecoder.proxy(at: gone, longSide: 360) }
        #expect(throws: PictureError.self) { try PictureDecoder.full(at: junk) }
    }
    @Test func heicHelperRoundTripsInTheSimulator() throws {   // Task 9's HEIF test depends on HEIC encoding in OpenCam Dev
        let url = try TestFiles.writeHEIC(width: 64, height: 48, rgb: SIMD3(0.4, 0.5, 0.6), to: TestFiles.directory().appending(path: "probe.HEIC"))
        #expect(try PictureDecoder.pixelSize(at: url) == CGSize(width: 64, height: 48))
        #expect(diff(try PixelReader.rgb(PictureDecoder.full(at: url), x: 32, y: 24), SIMD3(0.4, 0.5, 0.6)) < 0.03)
    }
    func diff(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float { ((a - b) * (a - b)).squareRoot().max() }
}
```

- [ ] **Step 2: Run to see them fail** — `scripts/test.sh LookRendererTests`. Expected: `cannot find 'LookRenderer' in scope`.
- [ ] **Step 3: Implement the renderer and decoder to the values above, then the test helpers.**
- [ ] **Step 4: Run to see them pass** — `scripts/test.sh LookRendererTests && scripts/test.sh PictureDecoderTests`. Expected: `** TEST SUCCEEDED **` twice. If `identityCubeKeepsPixelsSoTheDataOrderIsRight` swaps red and blue, the cube order is wrong; fix the compiler, never the test. If `heicHelperRoundTripsInTheSimulator` fails because the Simulator cannot encode HEIC, stop and report it: Task 9's HEIF export test and Call (5) need a ruling, so do not weaken the test.
- [ ] **Step 5: Commit**

```bash
git add OpenCam/Render OpenCam/App OpenCamTests
git commit -m "feat: add the look renderer and picture decoding with a capped proxy"
```

---

### Task 4: Library items, store, thumbnails and Simulator samples

**Files:**
- Create in `OpenCam/Library/`: `LibraryItemKind.swift`, `LibraryItem.swift`, `LibraryScanner.swift`, `ClipDuration.swift`, `ThumbnailCache.swift`, `ThumbnailState.swift`, `LibraryStore.swift`, `LibraryError.swift`, `SampleSeeder.swift`
- Create in `OpenCam/UI/Library/`: `ColourBarsPattern.swift`, `HueSweepPattern.swift`
- Modify: `OpenCam/Capture/CaptureFileKind.swift` (today `dng = "DNG"`, `heic = "HEIC"`, `mov = "MOV"`, `sidecar = "json"`; add `jpg = "JPG"`, `png = "PNG"`), `OpenCam/UI/ViewfinderStandIn.swift` (add `var showsCaption = true`; the caption overlay only when true)
- Test: `OpenCamTests/LibraryScannerTests.swift`, `OpenCamTests/ThumbnailCacheTests.swift`, `OpenCamTests/LibraryStoreTests.swift`, `OpenCamTests/SampleSeederTests.swift`

**Interfaces:**
- Consumes, as they are in the tree: `final class CaptureStore` (main-actor by default isolation; `static func appDefault() throws(CaptureStoreError) -> CaptureStore`, `init(directory: URL) throws(CaptureStoreError)`, `let directory: URL`, `func reserveSequence() -> Int` (starts above every `OC_` number in the folder at init), `func url(sequence: Int, kind: CaptureFileKind) -> URL`, `static func fileName(sequence:kind:) -> String`, `static func nextSequence(existingNames:) -> Int`); `ClipSidecar` (`requested: VideoOption`, `actual: ClipFacts?`, `outcome`, `recordedAt`, `error`; ISO 8601 dates) and `ClipFacts.durationSeconds`; Tasks 1 to 3.
- Produces:

```swift
nonisolated enum LibraryItemKind: String, Sendable { case photo, clip }
nonisolated struct LibraryItem: Sendable, Hashable, Identifiable {
    let kind: LibraryItemKind
    let stem: String                              // "OC_0001"; for a photo also the edit file's stem
    let pictureURL: URL                           // photo: the editable picture (HEIC, HEIF, JPG, JPEG, PNG, else the DNG); clip: the MOV
    let rawURL: URL?                              // photo: the DNG when the stem has one; clip: nil
    let sidecarURL: URL?                          // clip: "<stem>.json" when present; photo: nil
    let modified: Date                            // pictureURL's content modification date
    var id: String { get }                        // photo: stem; clip: stem + ".MOV"
    var isEditable: Bool { get }                  // kind == .photo
    var fileURLs: [URL] { get }                   // pictureURL, rawURL, sidecarURL, without nils or duplicates
}
nonisolated enum LibraryScanner {
    static let pictureExtensions: Set<String> = ["DNG", "HEIC", "HEIF", "JPG", "JPEG", "PNG"]   // compared uppercased
    static let clipExtensions: Set<String> = ["MOV"]
    static func items(in directory: URL) -> [LibraryItem]                   // reads names and modification dates, then `group`
    static func group(names: [String], directory: URL, modified: (String) -> Date = { _ in .distantPast }) -> [LibraryItem]
    static func sequence(ofStem stem: String) -> Int?                       // "OC_0012" -> 12, "IMG_7" -> nil
}
nonisolated enum ClipDuration {
    @concurrent static func seconds(of item: LibraryItem) async -> Double?  // the sidecar's actual.durationSeconds, else AVURLAsset's loaded duration; nil when neither reads
}
nonisolated enum ThumbnailState: Sendable { case loading, ready(CGImage), failed }
nonisolated struct ThumbnailCache: Sendable {
    static let longSide = 360
    static func appDefault() -> ThumbnailCache                              // Library/Caches/Thumbnails, created if missing
    init(directory: URL); let directory: URL
    static func key(fileName: String, modified: Date, edit: PhotoEdit) -> String   // "<fileName>-<ms since 1970>-<first 16 hex of SHA-256 of the adjustments as sorted-key JSON>.jpg"
    @concurrent func thumbnail(for item: LibraryItem, edit: PhotoEdit) async throws(PictureError) -> CGImage
    // photo: cached file, else proxy(360) through LookRenderer; clip: AVAssetImageGenerator frame at zero, preferred transform applied,
    // maximumSize 360 x 360, edit ignored; both written as Display P3 JPEG
}
nonisolated enum LibraryError: Error, CustomStringConvertible, Equatable {
    case deleteFailed(path: String, reason: String), editFailed(stem: String, reason: String)
    case newerEdit(path: String, version: Int)                              // from EditStoreError.newerVersion; shown as LibraryCopy.newerEdit
    case seedFailed(path: String, reason: String)                           // a sample that could not be rendered or written
}
@MainActor @Observable final class LibraryStore {
    init(captures: CaptureStore, edits: EditStore, looks: LookStore, thumbnails: ThumbnailCache)
    let captures: CaptureStore; let edits: EditStore; let lookStore: LookStore
    private(set) var items: [LibraryItem]         // photos and clips, newest first
    private(set) var looks: [Look]                // lookStore.all()
    func reload()                                 // items, photo edits and looks; an unreadable edit counts as PhotoEdit() and is logged
    func edit(for item: LibraryItem) -> PhotoEdit                          // PhotoEdit() for a clip
    func thumbnailKey(for item: LibraryItem) -> String
    func thumbnail(for item: LibraryItem) async -> ThumbnailState          // .failed when the file cannot be decoded
    func delete(_ items: [LibraryItem]) throws(LibraryError)
    // per item, all or nothing: a photo's edit file is removed first (EditStore.remove), then its fileURLs. An item whose edit is
    // newer (EditStoreError.newerVersion) is left whole, because an orphan .edit.json would still raise the next number.
    // The other items are still deleted; then reload, then throw the first error (.newerEdit before any other kind).
}
@MainActor enum SampleSeeder {
    static func seedIfEmpty(_ captures: CaptureStore) throws(LibraryError) -> Int   // 0 when Captures already has any library item, photo or clip; a failed render or write throws .seedFailed
}
struct ColourBarsPattern: View   // eight vertical bars (white, yellow, cyan, green, magenta, red, blue, black) over a bottom quarter grey ramp
struct HueSweepPattern: View     // hue left to right, saturation 1 at the top to 0 at the bottom
```

Grouping: photo files group by stem (name up to the first dot) into one photo item; each MOV is one clip item, carrying `<stem>.json` as its sidecar. `.edit.json`, sweep reports, sidecars and other files are not items; a sidecar whose clip is gone (a format sweep deletes its clips unless `-keepSweepClips on` and keeps their sidecars) is ignored entirely, never an item and never a placeholder. A sidecar belongs to the MOV whose `CaptureStore.clipKey(for:)` equals its own name with `json` replaced by `MOV`. Picture preference HEIC, HEIF, JPG, JPEG, PNG, DNG. Order: items with an `OC_` sequence first, highest sequence first (a photo before a clip of the same number, which captures never produce); the rest after them, by name. Samples: `ImageRenderer` at 672 x 504 pt and scale 3 (2016 x 1512 px), written as Display P3 JPEG through `LookRenderer.shared.context`, reserving numbers in this order: `ColourBarsPattern` (OC_0001), `HueSweepPattern` (OC_0002), `ViewfinderStandIn(showsCaption: false)` (OC_0003), so the newest item is the scene.

- [ ] **Step 1: Write the failing tests**

```swift
@Suite struct LibraryScannerTests {
    let dir = URL(filePath: "/tmp/Captures", directoryHint: .isDirectory)
    @Test func pairsDNGWithHEICListsClipsAndOrdersNewestFirst() throws {
        let items = LibraryScanner.group(names: ["OC_0001.DNG", "OC_0001.HEIC", "OC_0001.edit.json", "OC_0002.MOV", "OC_0002.json", "OC_0003.DNG", "OC_0006.MOV",
                                                 "OC_0010.jpg", "OC_0004.PNG", "IMG_7.jpeg", "notes.txt", "sweep-2026-11-09-143005.json", "OC_0005.HEIF",
                                                 "OC_0011.json"], directory: dir)   // OC_0011.json: a sweep clip's sidecar, clip deleted
        #expect(items.map(\.id) == ["OC_0010", "OC_0006.MOV", "OC_0005", "OC_0004", "OC_0003", "OC_0002.MOV", "OC_0001", "IMG_7"])
        #expect(items.map(\.kind) == [.photo, .clip, .photo, .photo, .photo, .clip, .photo, .photo])
        let paired = try #require(items.first { $0.id == "OC_0001" })
        #expect(paired.pictureURL.lastPathComponent == "OC_0001.HEIC"); #expect(paired.rawURL?.lastPathComponent == "OC_0001.DNG"); #expect(paired.fileURLs.count == 2)
        let rawOnly = try #require(items.first { $0.id == "OC_0003" })
        #expect(rawOnly.pictureURL.lastPathComponent == "OC_0003.DNG"); #expect(rawOnly.fileURLs.count == 1); #expect(rawOnly.isEditable)
        let clip = try #require(items.first { $0.id == "OC_0002.MOV" })
        #expect(!clip.isEditable); #expect(clip.rawURL == nil); #expect(clip.fileURLs.map(\.lastPathComponent) == ["OC_0002.MOV", "OC_0002.json"])
        #expect(items.first { $0.id == "OC_0006.MOV" }?.sidecarURL == nil)
        #expect(LibraryScanner.sequence(ofStem: "OC_12345") == 12345); #expect(LibraryScanner.sequence(ofStem: "IMG_7") == nil); #expect(LibraryScanner.sequence(ofStem: "OC_") == nil)
    }
    @Test func clipDurationComesFromTheSidecar() async throws {
        let dir = try TestFiles.directory()
        try Data("x".utf8).write(to: dir.appending(path: "OC_0002.MOV")); try Data("x".utf8).write(to: dir.appending(path: "OC_0003.MOV"))
        let option = VideoOption(lensID: "wide", codec: VideoCodec(family: .hevc, quality: "High", codecType: "hvc1", bitrateTier: .high), resolution: .named(width: 3840, height: 2160), frameRate: 30, colour: .rec709)
        let facts = ClipFacts(codecFourCC: "hvc1", width: 3840, height: 2160, nominalFrameRate: 30, durationSeconds: 42.5, frameCount: 1275, droppedFrames: 0, colour: .rec709, megabitsPerSecond: 44, hasAudio: true)
        try ClipSidecar(requested: option, actual: facts, outcome: "complete", recordedAt: .now, error: nil).encoded().write(to: dir.appending(path: "OC_0002.json"))
        let items = LibraryScanner.items(in: dir)
        #expect(await ClipDuration.seconds(of: try #require(items.first { $0.id == "OC_0002.MOV" })) == 42.5)
        #expect(await ClipDuration.seconds(of: try #require(items.first { $0.id == "OC_0003.MOV" })) == nil)   // no sidecar, unreadable file
    }
}

@Suite struct ThumbnailCacheTests {
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    @Test func keyFollowsNameDateAndEdit() {
        let plain = ThumbnailCache.key(fileName: "OC_0001.HEIC", modified: date, edit: PhotoEdit())
        #expect(plain.hasPrefix("OC_0001.HEIC-1800000000000-")); #expect(plain.hasSuffix(".jpg")); #expect(!plain.contains("/"))
        #expect(plain == ThumbnailCache.key(fileName: "OC_0001.HEIC", modified: date, edit: PhotoEdit()))
        #expect(plain != ThumbnailCache.key(fileName: "OC_0001.HEIC", modified: date.addingTimeInterval(1), edit: PhotoEdit()))
        #expect(plain != ThumbnailCache.key(fileName: "OC_0001.HEIC", modified: date, edit: PhotoEdit(adjustments: Adjustments().setting(.exposure, to: 0.1))))
        #expect(plain != ThumbnailCache.key(fileName: "OC_0002.HEIC", modified: date, edit: PhotoEdit()))
    }
    @Test func rendersAt360AndCaches() async throws {
        let captures = try TestFiles.directory(), cacheDirectory = try TestFiles.directory()
        _ = try TestFiles.writeJPEG(width: 1200, height: 800, rgb: SIMD3(0.5, 0.5, 0.5), to: captures.appending(path: "OC_0001.JPG"))
        let item = try #require(LibraryScanner.items(in: captures).first)
        let image = try await ThumbnailCache(directory: cacheDirectory).thumbnail(for: item, edit: PhotoEdit())
        #expect(image.width == 360); #expect(image.height == 240)
        let key = ThumbnailCache.key(fileName: "OC_0001.JPG", modified: item.modified, edit: PhotoEdit())
        #expect(FileManager.default.fileExists(atPath: cacheDirectory.appending(path: key).path(percentEncoded: false)))
    }
}

@MainActor @Suite struct LibraryStoreTests {
    static func make(_ dir: URL) throws -> LibraryStore {
        LibraryStore(captures: try CaptureStore(directory: dir), edits: EditStore(directory: dir),
                     looks: try LookStore(directory: TestFiles.directory()), thumbnails: ThumbnailCache(directory: try TestFiles.directory()))
    }
    @Test func reloadListsItemsAndDeleteRemovesOriginalsEditsAndSidecars() async throws {
        let dir = try TestFiles.directory()
        for name in ["OC_0001.DNG", "OC_0001.HEIC", "OC_0002.JPG", "OC_0003.MOV", "OC_0003.json"] { try Data("x".utf8).write(to: dir.appending(path: name)) }
        try EditStore(directory: dir).save(PhotoEdit(adjustments: Adjustments().setting(.exposure, to: 1)), stem: "OC_0001")
        let store = try Self.make(dir); store.reload()
        #expect(store.items.map(\.id) == ["OC_0003.MOV", "OC_0002", "OC_0001"])
        guard case .failed = await store.thumbnail(for: store.items[1]) else { Issue.record("an undecodable picture must give .failed"); return }
        guard case .failed = await store.thumbnail(for: store.items[0]) else { Issue.record("an undecodable clip must give .failed"); return }
        #expect(store.edit(for: store.items[2]).adjustments.exposure == 1); #expect(store.edit(for: store.items[0]) == PhotoEdit())
        try store.delete([store.items[0], store.items[2]])
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path(percentEncoded: false)) == ["OC_0002.JPG"])
        #expect(store.items.map(\.id) == ["OC_0002"])
    }
    @Test func deleteKeepsAPhotoWhoseEditIsNewer() throws {
        let dir = try TestFiles.directory()
        for name in ["OC_0001.JPG", "OC_0002.JPG"] { try Data("x".utf8).write(to: dir.appending(path: name)) }
        let newer = Data(#"{"version": 99, "adjustments": {"exposure": 1}}"#.utf8), editURL = dir.appending(path: "OC_0002.edit.json")
        try newer.write(to: editURL)
        let store = try Self.make(dir); store.reload()
        #expect(throws: LibraryError.newerEdit(path: editURL.path(percentEncoded: false), version: 99)) { try store.delete(store.items) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path(percentEncoded: false)).sorted() == ["OC_0002.JPG", "OC_0002.edit.json"])
        #expect(try Data(contentsOf: editURL) == newer); #expect(store.items.map(\.id) == ["OC_0002"])
    }
}

@MainActor @Suite struct SampleSeederTests {
    @Test func seedsThreePicturesOnlyIntoAnEmptyLibrary() throws {
        let dir = try TestFiles.directory(); let captures = try CaptureStore(directory: dir)
        #expect(try SampleSeeder.seedIfEmpty(captures) == 3)
        #expect(LibraryScanner.items(in: dir).map(\.pictureURL.lastPathComponent) == ["OC_0003.JPG", "OC_0002.JPG", "OC_0001.JPG"])
        #expect(try SampleSeeder.seedIfEmpty(captures) == 0)
        #expect(try PictureDecoder.pixelSize(at: dir.appending(path: "OC_0003.JPG")) == CGSize(width: 2016, height: 1512))
        let clipOnly = try TestFiles.directory()
        try Data("x".utf8).write(to: clipOnly.appending(path: "OC_0001.MOV"))
        #expect(try SampleSeeder.seedIfEmpty(CaptureStore(directory: clipOnly)) == 0)   // a clip is a library item
    }
}
```

- [ ] **Step 2: Run to see them fail** — `scripts/test.sh LibraryScannerTests`. Expected: `cannot find 'LibraryScanner' in scope`.
- [ ] **Step 3: Implement the files listed to the interfaces and rules above.**
- [ ] **Step 4: Run to see them pass** — `scripts/test.sh LibraryScannerTests && scripts/test.sh ThumbnailCacheTests && scripts/test.sh LibraryStoreTests && scripts/test.sh SampleSeederTests`, then `scripts/test.sh` (all suites, so the camera core still passes with the new `CaptureFileKind` cases). Expected: `** TEST SUCCEEDED **` each time.
- [ ] **Step 5: Commit**

```bash
git add OpenCam OpenCamTests
git commit -m "feat: add the library store with thumbnails and simulator samples"
```

---

### Task 5: Library screen

**Files:**
- Create in `OpenCam/UI/Library/`: `LibraryView.swift`, `LibraryCell.swift`, `LibrarySelectionBar.swift`; Create `OpenCam/Library/LibraryCopy.swift`
- Modify: `OpenCam/App/LaunchConfig.swift`, `OpenCam/App/LaunchScreen.swift` (add `library`, `editor`), `OpenCam/App/CameraModel.swift` (`init`'s `switch config.screen` maps `.library` and `.editor` to `sheet = nil`; `init(config:capabilities:isSimulator:defaults:capabilitySource:)` gains a last parameter `captureStore: CaptureStore? = nil` that seeds the existing `@ObservationIgnored private var captureStore`, which `loadLastCapture()` and `store(failureNotice:)` already use before creating one, so photos, recordings, sweeps and imports draw numbers from one store; adds the library members below. E1 shows no camera notice; any later one goes through `show(_:from:)` and `clearNotice(from:)` with a `NoticeSource`), `OpenCam/App/OpenCamApp.swift` (creates one `CaptureStore.appDefault()` and passes it to both `CameraModel` and `LibraryStore`, so captures and imports share one numbering in a run; then `EditStore` on the same folder, `LookStore.appDefault()`, `ThumbnailCache.appDefault()`; in the Simulator runs `SampleSeeder.seedIfEmpty` when `seedsSamples`; logs and shows no library if a store fails), `OpenCam/UI/CameraRootView.swift` (`init(model: CameraModel, library: LibraryStore?, launch: LaunchConfig)`; `.fullScreenCover(isPresented: $model.isLibraryPresented) { LibraryView(library:launch:) }`, presented only when `library` is non-nil), `scripts/shot.sh`, `OpenCamTests/LaunchConfigTests.swift`
- Test: `OpenCamTests/LibraryCopyTests.swift`, `OpenCamTests/LibraryLaunchTests.swift`

**Interfaces:**
- Consumes: Task 4 `LibraryStore`, `ThumbnailState`, `LibraryItem`, `ClipDuration`; Task 1 `EditorGroup`; camera core, as in the tree: `LaunchConfig` (`orientation`, `mode`, `screen`, `isRecording`, `simulatedState`, `freeSpaceMarginMB`, `keepsSweepClips`, `isScripted`), `LaunchScreen` (`main, record, sweep`), `CameraModel.init(config:capabilities:isSimulator:defaults:capabilitySource:)`, `CameraModel.isRecording`, `Theme`.
- Produces:

```swift
// LaunchConfig gains. -editorGroup sets isScripted when its value is an EditorGroup raw value. The three on/off flags set
// their property and isScripted only when the value is "on"; "off" or anything else leaves both unchanged.
var editorGroup: EditorGroup = .light   // -editorGroup light|colour|detail|effects|looks
var seedsSamples = false                // -seedSamples on   (honoured in the Simulator only)
var seedsLook = false                   // -seedLook on      (honoured in the Simulator only; used by Task 8)
var startsInSelectMode = false          // -librarySelect on
// CameraModel gains:
var isLibraryPresented: Bool            // true at launch when config.screen is .library or .editor
var canOpenLibrary: Bool { get }        // !isRecording && !isSweeping
func openLibrary()                      // sets isLibraryPresented when canOpenLibrary
nonisolated enum LibraryCopy {
    static let title = "Library", emptyTitle = "No photos yet", emptyDetail = "Take one or import from Photos."
    static let cannotOpen = "This photo could not be opened.", clipCannotOpen = "This video could not be opened."
    static let deleteFailed = "The items could not be deleted."
    static let newerEdit = "This photo was edited by a newer version of OpenCam."   // any save or remove that meets EditStoreError.newerVersion
    static let deleteMessage = "The files and their edits are removed from OpenCam. This cannot be undone."
    static func selectionTitle(count: Int) -> String   // "Select items", "1 selected", "3 selected"
    static func deleteTitle(count: Int) -> String      // "Delete 1 item?", "Delete 3 items?"
    static func duration(seconds: Double) -> String    // rounded down: 42.5 "0:42", 62 "1:02", 3725 "1:02:05"
}
struct LibraryView: View { let library: LibraryStore; let launch: LaunchConfig }
struct LibraryCell: View { let library: LibraryStore; let item: LibraryItem; let isSelecting: Bool; let isSelected: Bool }
struct LibrarySelectionBar: View { let count: Int; let onDelete: () -> Void }   // Task 8 adds the Apply look menu
```

`LibraryView`: `NavigationStack(path:)` over `[LibraryItem]`, title "Library", `.onAppear { library.reload() }`. Toolbar: leading `Button(role: .close)` dismisses; trailing "Select" toggles Select mode ("Done" while selecting). Content: when `items` is empty, `ContentUnavailableView("No photos yet", systemImage: "photo.on.rectangle", description: Text("Take one or import from Photos."))`; else a `LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 2)])` of square cells. `LibraryCell` runs `.task(id: library.thumbnailKey(for: item))`, shows a `ProgressView` while loading, the thumbnail with `.scaledToFill()` when ready, and `LibraryCopy.cannotOpen` (`clipCannotOpen` for a clip) in `.caption` text on `.secondary` background when failed. A clip cell adds a `play.fill` badge and `LibraryCopy.duration(seconds:)` from `ClipDuration.seconds(of:)` at the bottom trailing corner on a glass capsule (no duration text when it is nil), and its accessibility label reads "Video" and the duration; in Select mode a `checkmark.circle.fill` tinted `Theme.accent` marks a selected cell, and an accessibility label names the stem and "Selected". Outside Select mode a tap on a photo pushes the item (Task 7 adds the destination); a tap on a clip sets `previewURL` and `.quickLookPreview($previewURL)` plays it in the system preview. Clips are never pushed to the editor. Select mode: title `selectionTitle(count:)`; `LibrarySelectionBar` in `.toolbar` `.bottomBar` with "Delete" (`role: .destructive`, disabled at 0) opening `.confirmationDialog(deleteTitle(count:))` with message `deleteMessage` and a destructive "Delete"; a thrown `LibraryError` is logged and shows an alert titled `newerEdit` for `.newerEdit` and `deleteFailed` for any other case, never the error's description. `-librarySelect on` starts in Select mode with `items.first` selected.

`scripts/shot.sh` changes (today it hardcodes `mkdir -p docs/screenshots/p1a` and writes `docs/screenshots/p1a/$NAME.png` after `sleep 4`): the output folder becomes `${SHOT_DIR:-docs/screenshots/p1a}`, so camera core shots are unchanged; when `SHOT_FRESH=1`, `xcrun simctl uninstall "$UDID" local.opencam.app || true` runs before install so Captures and Looks start empty; `sleep 6` instead of 4, for seeding and thumbnails.

- [ ] **Step 1: Write the failing tests**

```swift
// Added to LaunchConfigTests
@Test func parsesLibraryAndEditorFlags() {
    let c = LaunchConfig.parse(["app", "-screen", "editor", "-editorGroup", "colour", "-seedSamples", "on", "-seedLook", "on", "-librarySelect", "on"])
    #expect(c.screen == .editor); #expect(c.editorGroup == .colour); #expect(c.seedsSamples); #expect(c.seedsLook); #expect(c.startsInSelectMode); #expect(c.isScripted)
    #expect(LaunchConfig.parse(["app", "-seedSamples", "on"]).isScripted)
    #expect(LaunchConfig.parse(["app", "-editorGroup", "masks", "-seedSamples", "off"]) == LaunchConfig())
}

@Suite struct LibraryCopyTests {
    @Test func copy() {
        #expect(LibraryCopy.selectionTitle(count: 0) == "Select items"); #expect(LibraryCopy.selectionTitle(count: 1) == "1 selected")
        #expect(LibraryCopy.selectionTitle(count: 3) == "3 selected")
        #expect(LibraryCopy.deleteTitle(count: 1) == "Delete 1 item?"); #expect(LibraryCopy.deleteTitle(count: 2) == "Delete 2 items?")
        #expect(LibraryCopy.duration(seconds: 42.5) == "0:42"); #expect(LibraryCopy.duration(seconds: 62) == "1:02"); #expect(LibraryCopy.duration(seconds: 3725) == "1:02:05")
        #expect(LibraryCopy.emptyTitle + ". " + LibraryCopy.emptyDetail == "No photos yet. Take one or import from Photos.")
        #expect(LibraryCopy.newerEdit == "This photo was edited by a newer version of OpenCam.")
    }
}

@MainActor @Suite struct LibraryLaunchTests {
    func model(_ args: [String]) throws -> CameraModel {
        CameraModel(config: .parse(["app"] + args), capabilities: try Fixture.load(), isSimulator: true, defaults: try Fixture.freshDefaults())
    }
    @Test func libraryScreensOpenTheLibrary() throws {
        #expect(try model(["-screen", "library"]).isLibraryPresented); #expect(try model(["-screen", "editor"]).isLibraryPresented)
        #expect(try model(["-screen", "library"]).sheet == nil); #expect(!(try model(["-screen", "record"]).isLibraryPresented))
    }
    @Test func libraryDoesNotOpenWhileRecording() throws {
        let recording = try model(["-recording", "on"]); recording.openLibrary(); #expect(!recording.isLibraryPresented)
        let idle = try model([]); idle.openLibrary(); #expect(idle.isLibraryPresented)
    }
    @Test func cameraUsesTheInjectedCaptureStore() throws {
        let dir = try TestFiles.directory()
        try Data("x".utf8).write(to: dir.appending(path: "OC_0007.HEIC"))
        let store = try CaptureStore(directory: dir)
        let model = CameraModel(config: LaunchConfig(), capabilities: try Fixture.load(), isSimulator: true, defaults: try Fixture.freshDefaults(), captureStore: store)
        model.loadLastCapture()
        #expect(model.lastCapture.map(CaptureStore.clipKey(for:)) == "OC_0007.HEIC")
        #expect(model.store(failureNotice: "x") === store)
    }
}
```

- [ ] **Step 2: Run to see them fail** — `scripts/test.sh LaunchConfigTests`. Expected: `value of type 'LaunchConfig' has no member 'editorGroup'`.
- [ ] **Step 3: Implement the changes and views listed.**
- [ ] **Step 4: Run to see them pass** — `scripts/test.sh LaunchConfigTests && scripts/test.sh LibraryCopyTests && scripts/test.sh LibraryLaunchTests`. Expected: `** TEST SUCCEEDED **` three times.
- [ ] **Step 5: Screenshot and look** (Read each PNG)

```bash
export SHOT_DIR=docs/screenshots/e1
SHOT_FRESH=1 scripts/shot.sh e1-library-empty-v -orientation portrait -screen library
SHOT_FRESH=1 scripts/shot.sh e1-library-empty-h -orientation landscape -screen library
SHOT_FRESH=1 scripts/shot.sh e1-library-v -orientation portrait -screen library -seedSamples on
scripts/shot.sh e1-library-h -orientation landscape -screen library -seedSamples on
scripts/shot.sh e1-library-select-v -orientation portrait -screen library -seedSamples on -librarySelect on
```

Pass when: the empty shots show "No photos yet" and "Take one or import from Photos." centred, the close button and "Select"; the seeded shots show three square thumbnails, the scene first, then the hue sweep, then the colour bars, nothing cropped badly or stretched, in both orientations; the select shot shows "1 selected", a checkmark on the scene, and "Delete" in the bottom bar; no text clipped; nothing drawn by hand where glass is expected. Samples hold no clip; the clip cell is checked by hand in Task 9.

- [ ] **Step 6: Commit**

```bash
git add OpenCam OpenCamTests scripts docs/screenshots/e1
git commit -m "feat: add the library screen with select mode and the empty state"
```

---

### Task 6: Import from the Photos library

**Files:**
- Create in `OpenCam/Library/`: `ImportCandidate.swift`, `ImportResult.swift`, `PhotoImporter.swift`
- Modify: `OpenCam/Library/LibraryStore.swift`, `OpenCam/Library/LibraryCopy.swift`, `OpenCam/UI/Library/LibraryView.swift`
- Test: `OpenCamTests/PhotoImporterTests.swift`

**Interfaces:**
- Consumes: Task 4 `LibraryStore`, `CaptureStore.reserveSequence()`, `CaptureStore.url(sequence:kind:)`, `CaptureFileKind` (`heic`, `jpg`, `png`, `dng`).
- Produces:

```swift
nonisolated struct ImportCandidate: Sendable { let data: Data; let contentType: UTType }
nonisolated struct ImportResult: Sendable, Equatable { let imported: [URL]; let failed: Int; var message: String? { get } }   // LibraryCopy.importResult
@MainActor enum PhotoImporter {
    static func fileKind(for type: UTType) -> CaptureFileKind?    // heic and heif -> .heic; jpeg -> .jpg; png -> .png; com.adobe.raw-image -> .dng; else nil
    static func importCandidates(_ candidates: [ImportCandidate], into captures: CaptureStore) -> ImportResult
    static func candidate(from item: PhotosPickerItem) async -> ImportCandidate?   // loadTransferable(type: Data.self); type = item.supportedContentTypes.first
}
extension LibraryStore { func importPhotos(_ candidates: [ImportCandidate]) -> ImportResult }   // imports, then reload
nonisolated extension LibraryCopy {   // nonisolated, as SessionConfiguration.swift:12 does: ImportResult.message calls it off the main actor
    static func importResult(imported: Int, failed: Int) -> String?
    // (0,0) nil; (1,0) "Imported 1 photo."; (3,0) "Imported 3 photos."; (2,1) "Imported 2 photos. 1 could not be imported.";
    // (0,1) "The photo could not be imported."; (0,2) "2 photos could not be imported."
}
```

Per candidate, in this order: map the type (nil fails it); prove it decodes with `CGImageSourceCreateWithData` and a 64 px `CGImageSourceCreateThumbnailAtIndex` (nil fails it); only then `reserveSequence()` and write with `Data.write(to:options: .atomic)`, so a failure never leaves a file or a number half-used. The original bytes are kept. A failed candidate logs `[PhotoImporter:importCandidates] …` with its type, never its bytes. UI: a `PhotosPicker(selection:maxSelectionCount: nil, selectionBehavior: .ordered, matching: .images, preferredItemEncoding: .current)` labelled `Label("Import", systemImage: "square.and.arrow.down")` in the trailing toolbar (hidden in Select mode); when the selection changes, load candidates, import, clear the selection, and show `message` in an alert with "OK".

- [ ] **Step 1: Write the failing tests**

```swift
@MainActor @Suite struct PhotoImporterTests {
    @Test func importsKeepTheirBytesAndContinueTheSequence() throws {
        let dir = try TestFiles.directory()
        try Data("x".utf8).write(to: dir.appending(path: "OC_0004.HEIC"))
        let jpeg = try TestFiles.jpegData(width: 40, height: 30, rgb: SIMD3(0.8, 0.2, 0.2)), png = try TestFiles.pngData(width: 30, height: 40, rgb: SIMD3(0.2, 0.8, 0.2))
        let result = PhotoImporter.importCandidates([ImportCandidate(data: jpeg, contentType: .jpeg), ImportCandidate(data: png, contentType: .png)],
                                                    into: try CaptureStore(directory: dir))
        #expect(result.imported.map(\.lastPathComponent) == ["OC_0005.JPG", "OC_0006.PNG"]); #expect(result.failed == 0)
        #expect(try Data(contentsOf: dir.appending(path: "OC_0005.JPG")) == jpeg); #expect(result.message == "Imported 2 photos.")
    }
    @Test func undecodableImportFailsAndLeavesCapturesUntouched() throws {   // Review Focus 4
        let dir = try TestFiles.directory()
        try Data("x".utf8).write(to: dir.appending(path: "OC_0001.HEIC"))
        let before = try FileManager.default.contentsOfDirectory(atPath: dir.path(percentEncoded: false)).sorted()
        let captures = try CaptureStore(directory: dir)
        let result = PhotoImporter.importCandidates([ImportCandidate(data: Data("not a picture".utf8), contentType: .jpeg),
                                                     ImportCandidate(data: try TestFiles.tiffData(width: 8, height: 8, rgb: SIMD3(0.5, 0.5, 0.5)), contentType: .tiff)], into: captures)
        #expect(result.imported.isEmpty); #expect(result.failed == 2); #expect(result.message == "2 photos could not be imported.")
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path(percentEncoded: false)).sorted() == before)
        #expect(PhotoImporter.importCandidates([ImportCandidate(data: Data("x".utf8), contentType: .heic)], into: captures).message == "The photo could not be imported.")
        #expect(captures.reserveSequence() == 2)   // failures used no number
    }
    @Test func fileKinds() throws {
        #expect(PhotoImporter.fileKind(for: .heic) == .heic); #expect(PhotoImporter.fileKind(for: .heif) == .heic)
        #expect(PhotoImporter.fileKind(for: .jpeg) == .jpg); #expect(PhotoImporter.fileKind(for: .png) == .png)
        #expect(PhotoImporter.fileKind(for: try #require(UTType("com.adobe.raw-image"))) == .dng)
        #expect(PhotoImporter.fileKind(for: .tiff) == nil); #expect(PhotoImporter.fileKind(for: .gif) == nil)
    }
    @Test func messages() {
        #expect(LibraryCopy.importResult(imported: 0, failed: 0) == nil); #expect(LibraryCopy.importResult(imported: 1, failed: 0) == "Imported 1 photo.")
        #expect(LibraryCopy.importResult(imported: 2, failed: 1) == "Imported 2 photos. 1 could not be imported.")
        #expect(LibraryCopy.importResult(imported: 0, failed: 1) == "The photo could not be imported.")
    }
}
```

- [ ] **Step 2: Run to see them fail** — `scripts/test.sh PhotoImporterTests`. Expected: `cannot find 'PhotoImporter' in scope`.
- [ ] **Step 3: Implement the files and the picker.**
- [ ] **Step 4: Run to see them pass** — `scripts/test.sh PhotoImporterTests`. Expected: `** TEST SUCCEEDED **`.
- [ ] **Step 5: Screenshot and look** — `SHOT_DIR=docs/screenshots/e1 scripts/shot.sh e1-library-import-v -orientation portrait -screen library -seedSamples on`. Pass when "Import" sits in the trailing toolbar beside "Select" and nothing else changed from `e1-library-v`.
- [ ] **Step 6: Commit**

```bash
git add OpenCam OpenCamTests docs/screenshots/e1
git commit -m "feat: import photos from the Photos library as new originals"
```

---

### Task 7: Editor screen

**Files:**
- Create: `OpenCam/Edit/EditorPhase.swift`, `OpenCam/Edit/EditorLayout.swift`
- Create in `OpenCam/UI/Editor/`: `EditorModel.swift`, `EditorView.swift`, `EditorPicture.swift`, `EditorPanel.swift`, `AdjustmentSlider.swift`
- Modify: `OpenCam/UI/Library/LibraryView.swift` (`.navigationDestination(for: LibraryItem.self)` builds an `EditorModel`; `-screen editor` pushes the first item with `isEditable` with `launch.editorGroup` once on appear; the destination is reached only from photos; a pop reloads the library), `OpenCam/Library/LibraryCopy.swift` (`saveFailed = "The edit could not be saved."`, added inside the enum body; `newerEdit` already exists from Task 5)
- Test: `OpenCamTests/EditorModelTests.swift`, `OpenCamTests/EditorLayoutTests.swift`, `OpenCamTests/EditorFixture.swift`

**Interfaces:**
- Consumes: Task 1 stores and `AdjustmentKey`, `EditorGroup`; Task 3 `PictureDecoder.proxy`, `LookRenderer.renderedCGImage`; Task 4 `LibraryItem`, `LibraryScanner`; Task 5 `LibraryCopy`.
- Produces:

```swift
nonisolated enum EditorPhase: Equatable, Sendable { case loading, ready, failed(String) }
nonisolated enum EditorLayout: Equatable, Sendable {
    case sideBySide, stacked
    static let panelWidth: CGFloat = 320
    static func choose(horizontal: UserInterfaceSizeClass?, vertical: UserInterfaceSizeClass?) -> EditorLayout   // regular width or compact height: side by side
}
@MainActor @Observable final class EditorModel {
    static let proxyLongSide = 2048
    init(item: LibraryItem, edits: EditStore, looks: LookStore, group: EditorGroup = .light, renderer: LookRenderer = .shared)
    let item: LibraryItem; var group: EditorGroup; var isShowingOriginal: Bool
    private let edits: EditStore; private let lookStore: LookStore   // the `looks:` argument; never stored as `looks`, which Task 8 uses for [Look]
    var adjustments: Adjustments                  // didSet schedules a preview render
    private(set) var lookName: String?; private(set) var phase: EditorPhase   // .loading until load() returns
    private(set) var preview: CGImage?; private(set) var original: CGImage?   // the edit on the proxy; the proxy unedited
    private(set) var proxySize: CGSize?; private(set) var renderedAdjustments: Adjustments?   // what `preview` shows
    private(set) var lastRenderPixelSize: CGSize?  // width x height of the CGImage the last completed renderedCGImage call returned,
                                                   // measured on that output; never copied from proxySize or the input
    private(set) var previewRenderCount: Int       // completed preview renders, the first one included
    var hasChanges: Bool { get }                  // adjustments or lookName differ from the loaded edit
    func load() async                             // edit (unreadable counts as none, logged), proxy off the main actor, first render;
                                                  // an edit whose version > PhotoEdit.currentVersion sets .failed(LibraryCopy.newerEdit) and decodes nothing
    func waitForPreview() async                   // returns when no render is running or pending
    func reset(_ key: AdjustmentKey); func resetAll()   // resetAll also clears lookName
    func save() -> Bool                           // false with phase .failed(LibraryCopy.cannotOpen) when the original is gone, nothing written;
                                                  // EditStoreError.newerVersion -> false with .failed(LibraryCopy.newerEdit); other EditStoreError -> .failed(LibraryCopy.saveFailed)
}
struct EditorView: View { @Bindable var model: EditorModel; let onDone: () -> Void }
struct AdjustmentSlider: View { let key: AdjustmentKey; @Binding var value: Double; let onReset: () -> Void }
// OpenCamTests: @MainActor enum EditorFixture { static func make(width: Int, height: Int) async throws -> (model: EditorModel, captures: URL, looks: LookStore) }
//   writes a mid-grey OC_0001.JPG, scans it, loads the model with an empty LookStore
```

Rendering rule (not fixed by the signatures): at most one render runs; a change while it runs only replaces the pending value; when a render finishes, the latest pending value renders once. Every render takes the in-memory proxy, never the file. A decode failure in `load` sets `.failed(LibraryCopy.cannotOpen)`; an `EditStoreError` in `save` is logged and sets `.failed(LibraryCopy.newerEdit)` for `.newerVersion`, else `.failed(LibraryCopy.saveFailed)`; no error description is ever shown. `lastRenderPixelSize` is set in the render path from the returned `CGImage`'s `width` and `height`, so a full-size render would show up as 8064 x 6048.

`EditorView`: `EditorLayout.choose` from the size-class environment values; side by side puts `EditorPicture` beside an `EditorPanel` of width 320, stacked puts the picture above the panel. `EditorPicture` shows `original` while `isShowingOriginal`, else `preview`, `.scaledToFit()`; `onLongPressGesture(minimumDuration: 0.15, perform: {}, onPressingChanged:)` sets `isShowingOriginal`, and a glass capsule reads "Original" while held; in `.failed(m)` it shows `m` instead of the picture and disables the panel and toolbar except Done. `EditorPanel`: a segmented `Picker` over `EditorGroup.allCases.filter { $0 != .looks }` (Task 8 removes the filter), then the group's `AdjustmentSlider`s in a `ScrollView`. `AdjustmentSlider`: the title and `key.valueText(value)` (monospaced digits) on one row, a system `Slider(value:in: key.range, step: key.step)` below; double-tapping the title calls `onReset`, also offered as the accessibility action "Reset". Toolbar: "Done" (`.confirmationAction`) calls `onDone` without saving when `phase` is `.failed` (so a failed photo never traps the user), otherwise calls `save()` and then `onDone` when it returns true; "Reset all" disabled when `adjustments.isIdentity && lookName == nil`. The navigation back button is hidden; the title is `item.stem`.

- [ ] **Step 1: Write the failing tests**

```swift
@MainActor @Suite struct EditorModelTests {
    @Test func fortyEightMegapixelOriginalRendersOnlyTheProxy() async throws {   // Review Focus 2
        let (model, _, _) = try await EditorFixture.make(width: 8064, height: 6048)
        #expect(model.phase == .ready); #expect(model.proxySize == CGSize(width: 2048, height: 1536))
        let rendersBefore = model.previewRenderCount
        for step in 1...30 { model.adjustments.exposure = Double(step) / 10 }
        await model.waitForPreview()
        #expect(model.previewRenderCount > rendersBefore)   // the slider change really rendered
        let size = try #require(model.lastRenderPixelSize)   // measured on the CGImage the renderer returned
        #expect(max(size.width, size.height) <= 2048); #expect(size == CGSize(width: 2048, height: 1536))
        #expect(model.renderedAdjustments == model.adjustments); #expect(model.previewRenderCount <= 3)
    }
    @Test func opensWithItsSavedEdit() async throws {
        let dir = try TestFiles.directory()
        _ = try TestFiles.writeJPEG(width: 400, height: 300, rgb: SIMD3(0.5, 0.5, 0.5), to: dir.appending(path: "OC_0001.JPG"))
        try EditStore(directory: dir).save(PhotoEdit(adjustments: Adjustments().setting(.contrast, to: 25), lookName: "Warm fade"), stem: "OC_0001")
        let item = try #require(LibraryScanner.items(in: dir).first)
        let model = EditorModel(item: item, edits: EditStore(directory: dir), looks: try LookStore(directory: TestFiles.directory()))
        await model.load()
        #expect(model.adjustments.contrast == 25); #expect(model.lookName == "Warm fade"); #expect(!model.hasChanges); #expect(model.preview != nil)
    }
    @Test func resetsAndSave() async throws {
        let (model, dir, _) = try await EditorFixture.make(width: 400, height: 300)
        model.adjustments.shadows = 40; model.adjustments.tint = -10; #expect(model.hasChanges)
        model.reset(.shadows); #expect(model.adjustments.shadows == 0); #expect(model.adjustments.tint == -10)
        #expect(model.save()); #expect(try EditStore(directory: dir).load(stem: "OC_0001").adjustments.tint == -10)
        model.resetAll(); #expect(model.adjustments.isIdentity); #expect(model.save())
        #expect(!FileManager.default.fileExists(atPath: dir.appending(path: "OC_0001.edit.json").path(percentEncoded: false)))
    }
    @Test func originalRemovedWhileOpenSaysCannotOpen() async throws {   // Review Focus 5
        let (model, dir, _) = try await EditorFixture.make(width: 400, height: 300)
        try FileManager.default.removeItem(at: dir.appending(path: "OC_0001.JPG"))
        model.adjustments.exposure = 1
        await model.waitForPreview()
        #expect(!model.save()); #expect(model.phase == .failed("This photo could not be opened."))
        #expect(!FileManager.default.fileExists(atPath: dir.appending(path: "OC_0001.edit.json").path(percentEncoded: false)))
    }
    @Test func undecodableOriginalSaysCannotOpen() async throws {
        let dir = try TestFiles.directory()
        try Data("nope".utf8).write(to: dir.appending(path: "OC_0001.JPG"))
        let model = EditorModel(item: try #require(LibraryScanner.items(in: dir).first), edits: EditStore(directory: dir), looks: try LookStore(directory: TestFiles.directory()))
        await model.load()
        #expect(model.phase == .failed("This photo could not be opened.")); #expect(model.preview == nil)
    }
    @Test func editFromANewerVersionOpensReadOnly() async throws {
        let dir = try TestFiles.directory()
        _ = try TestFiles.writeJPEG(width: 400, height: 300, rgb: SIMD3(0.5, 0.5, 0.5), to: dir.appending(path: "OC_0001.JPG"))
        let newer = Data(#"{"version": 99, "adjustments": {"exposure": 1}, "masks": []}"#.utf8), editURL = dir.appending(path: "OC_0001.edit.json")
        try newer.write(to: editURL)
        let model = EditorModel(item: try #require(LibraryScanner.items(in: dir).first), edits: EditStore(directory: dir), looks: try LookStore(directory: TestFiles.directory()))
        await model.load()
        #expect(model.phase == .failed("This photo was edited by a newer version of OpenCam."))
        #expect(!model.save()); #expect(try Data(contentsOf: editURL) == newer)
    }
}

@Suite struct EditorLayoutTests {
    @Test func layouts() {
        #expect(EditorLayout.choose(horizontal: .regular, vertical: .regular) == .sideBySide)
        #expect(EditorLayout.choose(horizontal: .compact, vertical: .compact) == .sideBySide)
        #expect(EditorLayout.choose(horizontal: .compact, vertical: .regular) == .stacked)
        #expect(EditorLayout.choose(horizontal: nil, vertical: nil) == .stacked)
    }
}
```

- [ ] **Step 2: Run to see them fail** — `scripts/test.sh EditorModelTests`. Expected: `cannot find 'EditorModel' in scope`.
- [ ] **Step 3: Implement the files listed to the rules above.**
- [ ] **Step 4: Run to see them pass** — `scripts/test.sh EditorModelTests && scripts/test.sh EditorLayoutTests`. Expected: `** TEST SUCCEEDED **` twice.
- [ ] **Step 5: Screenshot and look**

```bash
export SHOT_DIR=docs/screenshots/e1
SHOT_FRESH=1 scripts/shot.sh e1-editor-light-v -orientation portrait -screen editor -seedSamples on
scripts/shot.sh e1-editor-light-h -orientation landscape -screen editor -seedSamples on
for g in colour detail effects; do scripts/shot.sh "e1-editor-$g-v" -orientation portrait -screen editor -seedSamples on -editorGroup "$g"; done
scripts/shot.sh e1-editor-effects-h -orientation landscape -screen editor -seedSamples on -editorGroup effects
```

Pass when: portrait shots have the scene above the panel, landscape shots have it beside a 320 pt panel; the segmented control reads Light, Colour, Detail, Effects with the launch group selected; each group lists exactly its sliders by name with values "0.0" (Exposure) or "0"; toolbar "Done" and "Reset all" (disabled); title "OC_0003"; the picture is not stretched; nothing clipped in landscape.

- [ ] **Step 6: Commit**

```bash
git add OpenCam OpenCamTests docs/screenshots/e1
git commit -m "feat: add the editor with light, colour, detail and effects sliders"
```

---

### Task 8: Looks in the editor and in the library

**Files:**
- Create: `OpenCam/Library/LookSeeder.swift`, `OpenCam/Library/LookChange.swift`; in `OpenCam/UI/Editor/`: `LooksPanel.swift`, `LookTile.swift`
- Modify: `OpenCam/UI/Editor/EditorModel.swift`, `OpenCam/UI/Editor/EditorPanel.swift` (Looks segment), `OpenCam/Library/LibraryStore.swift`, `OpenCam/UI/Library/LibrarySelectionBar.swift`, `OpenCam/UI/Library/LibraryView.swift`, `OpenCam/App/OpenCamApp.swift` (`seedsLook` in the Simulator calls `LookSeeder.seedWarmFade`)
- Test: `OpenCamTests/LookFlowTests.swift`, `OpenCamTests/LibraryLookTests.swift`

**Interfaces:**
- Consumes: Task 1 `LookStore`, `Look`, `PhotoEdit`; Task 4 `LibraryStore`; Task 7 `EditorModel`, `EditorFixture`.
- Produces:

```swift
nonisolated enum LookSeeder {
    static let warmFadeName = "Warm fade"
    static let warmFade: Adjustments   // exposure 0.3, contrast -15, highlights -20, shadows 25, blacks 15, temperature 20, tint 5, vibrance 10, saturation -10, grain 20, vignette -15
    static func seedWarmFade(into store: LookStore) throws(LookStoreError) -> Look?   // nil when a look named "Warm fade" exists
}
// EditorModel gains a stored `private(set) var looks: [Look]` (Task 7's LookStore is the separate `lookStore`), loaded in load()
// and refreshed from lookStore.all() after every save, rename, duplicate and delete, and:
extension EditorModel {
    func applyLook(_ look: Look?)                                   // copies adjustments and name; nil clears to Adjustments() and no look
    func saveAsLook(named name: String) throws(LookStoreError) -> Look
    func renameLook(_ id: UUID, to name: String) throws(LookStoreError)
    func duplicateLook(_ id: UUID) throws(LookStoreError)
    func deleteLook(_ id: UUID) throws(LookStoreError)              // the current edit keeps its values and lookName
    func lookPreview(_ look: Look?) async -> CGImage?               // the look on a copy of the proxy with long side 240
}
extension LibraryStore {
    func applyLook(_ look: Look, to items: [LibraryItem]) throws(LibraryError) -> LookChange
    // each photo's edit becomes PhotoEdit(adjustments: look.adjustments, lookName: look.name); clips skipped; a photo whose save throws
    // EditStoreError.newerVersion is left unchanged and counted in newerSkipped; any other EditStoreError throws .editFailed after the rest; then reload
    func removeLook(from items: [LibraryItem]) throws(LibraryError) -> LookChange
    // removes the edit of photos whose lookName is set; others and clips untouched; newerVersion counts in newerSkipped as above; then reload
}
nonisolated struct LookChange: Sendable, Equatable {        // OpenCam/Library/LookChange.swift
    nonisolated enum Action: Sendable { case applied, removed }
    let action: Action; let photosChanged: Int; let clipsSkipped: Int; let newerSkipped: Int
    var message: String { get }
    // first sentence: photosChanged 0 "No photos were changed."; applied 1 "Applied to 1 photo.", N "Applied to N photos.";
    //   removed 1 "Look removed from 1 photo.", N "Look removed from N photos."
    // then, only when clipsSkipped > 0: " 1 video was skipped." / " N videos were skipped."
    // then, only when newerSkipped > 0: " 1 photo was edited by a newer version of OpenCam and was skipped." /
    //   " N photos were edited by a newer version of OpenCam and were skipped."
}
struct LooksPanel: View { @Bindable var model: EditorModel }
struct LookTile: View { let title: String; let image: CGImage?; let isSelected: Bool }
```

`LooksPanel`: a `LazyVGrid` (adaptive, minimum 96) with "None" first, then every look; each `LookTile` loads its image with `.task(id:)` from `lookPreview`, shows the name below, and is selected when its name equals `model.lookName` ("None" when nil); a tap calls `applyLook`. Each look tile has a `.contextMenu` with "Rename", "Duplicate" and "Delete" (`role: .destructive`); Rename and "Save as look" (a bordered button under the grid) open an alert with a `TextField("Name", …)` and "Save" disabled while `LookStore.nameProblem` returns a message, shown as the alert message; Delete asks `.confirmationDialog("Delete \u{201C}\(name)\u{201D}?")` with the message "Photos that used it keep their edits." In the library, `LibrarySelectionBar` gains a `Menu("Apply look")` (disabled at 0 selected) listing every look by name, a divider, then "Remove look"; applying or removing reloads the grid and shows the returned `LookChange.message` in an alert with "OK"; a thrown `LibraryError` is logged and shows `LibraryCopy.saveFailed`, never its description.

- [ ] **Step 1: Write the failing tests**

```swift
@MainActor @Suite struct LookFlowTests {
    @Test func savingAndApplyingALookCopiesItsValues() async throws {
        let (model, _, _) = try await EditorFixture.make(width: 400, height: 300)
        model.adjustments.temperature = 30; model.adjustments.grain = 10
        let look = try model.saveAsLook(named: "  Golden ")
        #expect(look.name == "Golden"); #expect(model.looks.map(\.name) == ["Golden"])
        model.resetAll(); model.applyLook(look)
        #expect(model.adjustments == look.adjustments); #expect(model.lookName == "Golden")
        model.applyLook(nil); #expect(model.adjustments.isIdentity); #expect(model.lookName == nil)
        #expect(throws: LookStoreError.emptyName) { try model.saveAsLook(named: " ") }
    }
    @Test func renameDuplicateDeleteUpdateTheList() async throws {
        let (model, _, _) = try await EditorFixture.make(width: 400, height: 300)
        let look = try model.saveAsLook(named: "Golden"); model.applyLook(look)
        try model.renameLook(look.id, to: "Gold"); try model.duplicateLook(look.id)
        #expect(model.looks.map(\.name) == ["Gold", "Gold copy"])
        try model.deleteLook(look.id)
        #expect(model.looks.map(\.name) == ["Gold copy"]); #expect(model.lookName == "Golden"); #expect(model.adjustments == look.adjustments)
    }
    @Test func lookPreviewIsSmall() async throws {
        let (model, _, _) = try await EditorFixture.make(width: 1200, height: 800)
        let image = try #require(await model.lookPreview(Look(id: UUID(), name: "A", adjustments: LookSeeder.warmFade, createdAt: .now)))
        #expect(max(image.width, image.height) == 240)
    }
    @Test func seedLookOnce() throws {
        let store = try LookStore(directory: TestFiles.directory())
        #expect(try LookSeeder.seedWarmFade(into: store)?.name == "Warm fade"); #expect(try LookSeeder.seedWarmFade(into: store) == nil)
        #expect(store.all().count == 1); #expect(store.all().first?.adjustments == LookSeeder.warmFade)
    }
}

@MainActor @Suite struct LibraryLookTests {
    func setUp() throws -> (LibraryStore, URL) {
        let dir = try TestFiles.directory()
        for name in ["OC_0001.JPG", "OC_0002.JPG", "OC_0003.JPG", "OC_0004.MOV"] { try Data("x".utf8).write(to: dir.appending(path: name)) }
        try EditStore(directory: dir).save(PhotoEdit(adjustments: Adjustments().setting(.exposure, to: 1)), stem: "OC_0003")
        let store = try LibraryStoreTests.make(dir); store.reload()
        return (store, dir)
    }
    @Test func applyToManyAndRemove() throws {
        let (store, dir) = try setUp()
        let look = try store.lookStore.save(name: "Warm fade", adjustments: LookSeeder.warmFade)
        let applied = try store.applyLook(look, to: store.items.filter { $0.stem != "OC_0003" })   // OC_0004.MOV, OC_0002, OC_0001
        #expect(applied == LookChange(action: .applied, photosChanged: 2, clipsSkipped: 1, newerSkipped: 0)); #expect(applied.message == "Applied to 2 photos. 1 video was skipped.")
        #expect(!FileManager.default.fileExists(atPath: dir.appending(path: "OC_0004.edit.json").path(percentEncoded: false)))
        let edits = EditStore(directory: dir), expected = PhotoEdit(adjustments: LookSeeder.warmFade, lookName: "Warm fade")
        #expect(try edits.load(stem: "OC_0001") == expected); #expect(try edits.load(stem: "OC_0002") == expected)
        #expect(store.edit(for: try #require(store.items.first { $0.stem == "OC_0001" })) == expected)   // the store reloaded
        let removed = try store.removeLook(from: store.items)
        #expect(removed.message == "Look removed from 2 photos. 1 video was skipped.")
        #expect(try edits.load(stem: "OC_0001") == PhotoEdit()); #expect(try edits.load(stem: "OC_0003").adjustments.exposure == 1)
    }
    @Test func messagesForEveryCount() {
        func message(_ action: LookChange.Action, _ photos: Int, _ clips: Int, _ newer: Int) -> String {
            LookChange(action: action, photosChanged: photos, clipsSkipped: clips, newerSkipped: newer).message
        }
        #expect(message(.applied, 0, 0, 0) == "No photos were changed."); #expect(message(.removed, 0, 0, 0) == "No photos were changed.")
        #expect(message(.applied, 1, 0, 0) == "Applied to 1 photo."); #expect(message(.applied, 3, 0, 0) == "Applied to 3 photos.")
        #expect(message(.removed, 1, 0, 0) == "Look removed from 1 photo."); #expect(message(.removed, 3, 0, 0) == "Look removed from 3 photos.")
        #expect(message(.applied, 0, 1, 0) == "No photos were changed. 1 video was skipped.")
        #expect(message(.applied, 2, 2, 0) == "Applied to 2 photos. 2 videos were skipped.")
        #expect(message(.applied, 1, 0, 1) == "Applied to 1 photo. 1 photo was edited by a newer version of OpenCam and was skipped.")
        #expect(message(.removed, 0, 1, 2) == "No photos were changed. 1 video was skipped. 2 photos were edited by a newer version of OpenCam and were skipped.")
    }
    @Test func newerEditsAreSkippedAndUntouched() throws {
        let (store, dir) = try setUp()
        let newer = Data(#"{"version": 99, "lookName": "Old", "adjustments": {"exposure": 2}}"#.utf8), editURL = dir.appending(path: "OC_0002.edit.json")
        try newer.write(to: editURL); store.reload()
        let look = try store.lookStore.save(name: "Warm fade", adjustments: LookSeeder.warmFade)
        let photos = store.items.filter { $0.stem == "OC_0001" || $0.stem == "OC_0002" }
        #expect(try store.applyLook(look, to: photos) == LookChange(action: .applied, photosChanged: 1, clipsSkipped: 0, newerSkipped: 1))
        #expect(try store.removeLook(from: store.items.filter { $0.stem == "OC_0002" }) == LookChange(action: .removed, photosChanged: 0, clipsSkipped: 0, newerSkipped: 1))
        #expect(try Data(contentsOf: editURL) == newer)
    }
    @Test func deletingALookKeepsPhotosThatUsedIt() throws {   // Review Focus 3
        let (store, dir) = try setUp()
        let look = try store.lookStore.save(name: "Warm fade", adjustments: LookSeeder.warmFade)
        let item = try #require(store.items.first { $0.stem == "OC_0001" })
        _ = try store.applyLook(look, to: [item])
        _ = try store.lookStore.rename(look.id, to: "Cool"); try store.lookStore.delete(look.id); store.reload()
        #expect(store.looks.isEmpty)
        #expect(store.edit(for: item) == PhotoEdit(adjustments: LookSeeder.warmFade, lookName: "Warm fade"))
        #expect(try EditStore(directory: dir).load(stem: "OC_0001") == PhotoEdit(adjustments: LookSeeder.warmFade, lookName: "Warm fade"))
    }
}
```

- [ ] **Step 2: Run to see them fail** — `scripts/test.sh LookFlowTests`. Expected: `value of type 'EditorModel' has no member 'saveAsLook'`.
- [ ] **Step 3: Implement the changes listed.**
- [ ] **Step 4: Run to see them pass** — `scripts/test.sh LookFlowTests && scripts/test.sh LibraryLookTests && scripts/test.sh EditorModelTests`. Expected: `** TEST SUCCEEDED **` three times.
- [ ] **Step 5: Screenshot and look**

```bash
export SHOT_DIR=docs/screenshots/e1
SHOT_FRESH=1 scripts/shot.sh e1-editor-looks-v -orientation portrait -screen editor -seedSamples on -seedLook on -editorGroup looks
scripts/shot.sh e1-editor-looks-h -orientation landscape -screen editor -seedSamples on -seedLook on -editorGroup looks
scripts/shot.sh e1-library-select-looks-v -orientation portrait -screen library -seedSamples on -seedLook on -librarySelect on
```

Pass when: the segmented control now ends with Looks, selected; "None" is selected and shows the scene unedited; "Warm fade" shows the same scene visibly warmer, flatter and with darker corners; "Save as look" sits under the grid; the select shot shows "Apply look" and "Delete" in the bottom bar.

- [ ] **Step 6: Commit**

```bash
git add OpenCam OpenCamTests docs/screenshots/e1
git commit -m "feat: save, apply and manage looks in the editor and the library"
```

---

### Task 9: Export, the camera's Library item, and E1 verification

**Files:**
- Create in `OpenCam/Render/`: `PhotoExporter.swift`, `ExportFormat.swift`, `ExportError.swift`; Create `OpenCam/UI/Editor/ShareSheet.swift`
- Modify: `OpenCam/UI/Editor/EditorModel.swift` (`export()`, `alertMessage`), `OpenCam/UI/Editor/EditorView.swift` ("Export" toolbar item, `ProgressView` while exporting, share sheet, alert), `OpenCam/Library/LibraryCopy.swift` (`exportFailed = "The photo could not be exported."`), `OpenCam/UI/LibraryThumbnail.swift` (its `Button` calls `model.openLibrary()` instead of setting `previewURL`; `@State previewURL` and `.quickLookPreview($previewURL)` are removed, because Library now previews photos and clips; `.disabled(model.lastCapture == nil)` becomes `.disabled(!model.canOpenLibrary)`, so an empty folder still opens Library's empty state; the `QLThumbnailGenerator` image and `.task(id: model.lastCapture) { model.loadLastCapture() … }` stay; `StripToolbar`'s `.library` case already shows `LibraryThumbnail(model:)` and is unchanged), `OpenCam/App/CameraModel.swift` (adds `func refreshLastCapture()`: `lastCapture = captureStore?.latestCapture()`, creating the store as `loadLastCapture()` does, so a capture deleted in Library stops showing), `OpenCam/Capture/CaptureStore.swift` (`latestCaptureName`'s rank list `[.heic, .mov, .dng]` becomes `[.heic, .jpg, .png, .mov, .dng]`, so imports and samples show; the existing `StatusTextTests` expectations still hold; `nextSequence(existingNames:)` and `latestCaptureName` stop parsing `OC_` numbers themselves and call the nonisolated `LibraryScanner.sequence(ofStem:)` on the name up to its first dot, so one parser serves capture numbering and the library, and `.edit.json` names still count toward the next number), `OpenCam/UI/CameraRootView.swift` (the library cover's `onDismiss` calls `model.refreshLastCapture()`)
- Test: `OpenCamTests/PhotoExporterTests.swift`, `OpenCamTests/EditorExportTests.swift`, `OpenCamTests/LastCaptureTests.swift` (the camera's last-capture tests, kept out of the editor suite); Modify `OpenCamTests/TestFiles.swift` (`static func snapshot(_ directory: URL) throws -> [String: Date]`, names to modification dates)

**Interfaces:**
- Consumes: Task 3 `PictureDecoder.full`, `LookRenderer`; Task 4 `LibraryItem`; Task 7 `EditorModel`; Task 5 `CameraModel.openLibrary()`, `canOpenLibrary`, the injected `captureStore`; from the tree: `struct LibraryThumbnail: View { let model: CameraModel }`, `CameraModel.lastCapture: URL?`, `CameraModel.loadLastCapture()`, `CaptureStore.latestCapture() -> URL?`, `static func latestCaptureName(_ names: [String]) -> String?` (HEIC, then MOV, then DNG within a number; sidecars and sweep reports never offered).
- Produces:

```swift
nonisolated enum ExportFormat: String, Sendable {
    case heif = "HEIC", jpeg = "JPG"
    static func of(_ pictureURL: URL) -> ExportFormat   // JPG or JPEG original -> .jpeg; anything else -> .heif
}
nonisolated enum ExportError: Error, CustomStringConvertible, Equatable { case sourceMissing(path: String), undecodable(path: String), writeFailed(path: String, reason: String) }
nonisolated struct PhotoExporter: Sendable {
    static func appDefault() -> PhotoExporter          // tmp/Export, created if missing
    init(directory: URL, renderer: LookRenderer = .shared)
    @concurrent func export(_ item: LibraryItem, edit: PhotoEdit) async throws(ExportError) -> URL   // "<stem>-edited.HEIC" or ".JPG"; replaces an older export of that name
}
// EditorModel gains stored `var alertMessage: String?`, `private(set) var isExporting: Bool`, an init parameter `exporter: PhotoExporter = .appDefault()`, and:
extension EditorModel {
    func export() async -> URL?        // nil on failure: sourceMissing sets phase .failed(LibraryCopy.cannotOpen); others set alertMessage = LibraryCopy.exportFailed
}
struct ShareSheet: UIViewControllerRepresentable { let url: URL }   // UIActivityViewController(activityItems: [url])
```

Export decodes the full-size original with `PictureDecoder.full`, applies `LookRenderer.render(_:adjustments:)` with the current (unsaved) adjustments, and writes with `context.writeHEIFRepresentation(of:to:format: .RGBA8, colorSpace: displayP3, options:)` or `writeJPEGRepresentation(of:to:colorSpace: displayP3, options:)`, quality `0.9` (`kCGImageDestinationLossyCompressionQuality`). The pixels are already upright, so no orientation tag is written. It never writes into the item's folder.

- [ ] **Step 1: Write the failing tests**

```swift
@Suite struct PhotoExporterTests {
    @Test func exportsFullSizeJPEGOutsideCaptures() async throws {
        let captures = try TestFiles.directory(), out = try TestFiles.directory()
        _ = try TestFiles.writeJPEG(width: 3000, height: 2000, rgb: SIMD3(0.5, 0.5, 0.5), to: captures.appending(path: "OC_0001.JPG"))
        let before = try TestFiles.snapshot(captures)
        let item = try #require(LibraryScanner.items(in: captures).first)
        let url = try await PhotoExporter(directory: out).export(item, edit: PhotoEdit(adjustments: Adjustments().setting(.exposure, to: 1)))
        #expect(url.lastPathComponent == "OC_0001-edited.JPG")
        #expect(url.deletingLastPathComponent().standardizedFileURL == out.standardizedFileURL)
        #expect(try PictureDecoder.pixelSize(at: url) == CGSize(width: 3000, height: 2000))
        #expect(abs(try PixelReader.rgb(PictureDecoder.full(at: url), x: 1500, y: 1000).x - 0.686) < 0.02)
        #expect(try TestFiles.snapshot(captures) == before)
    }
    @Test func heicOriginalExportsAsHEIF() async throws {
        let captures = try TestFiles.directory()
        _ = try TestFiles.writeHEIC(width: 400, height: 300, rgb: SIMD3(0.4, 0.5, 0.6), to: captures.appending(path: "OC_0002.HEIC"))
        let item = try #require(LibraryScanner.items(in: captures).first)
        let url = try await PhotoExporter(directory: try TestFiles.directory()).export(item, edit: PhotoEdit())
        #expect(url.lastPathComponent == "OC_0002-edited.HEIC"); #expect(try PictureDecoder.pixelSize(at: url) == CGSize(width: 400, height: 300))
        #expect(ExportFormat.of(URL(filePath: "/x/OC_0003.jpeg")) == .jpeg); #expect(ExportFormat.of(URL(filePath: "/x/OC_0003.DNG")) == .heif)
    }
    @Test func missingSourceThrows() async throws {   // Review Focus 5
        let captures = try TestFiles.directory()
        _ = try TestFiles.writeJPEG(width: 40, height: 30, rgb: SIMD3(0.5, 0.5, 0.5), to: captures.appending(path: "OC_0004.JPG"))
        let item = try #require(LibraryScanner.items(in: captures).first)
        try FileManager.default.removeItem(at: item.pictureURL)
        await #expect(throws: ExportError.sourceMissing(path: item.pictureURL.path(percentEncoded: false))) {
            try await PhotoExporter(directory: try TestFiles.directory()).export(item, edit: PhotoEdit())
        }
    }
}

@MainActor @Suite struct EditorExportTests {
    @Test func exportFromTheEditorAndAfterTheOriginalIsGone() async throws {
        let (model, dir, _) = try await EditorFixture.make(width: 400, height: 300)
        model.adjustments.saturation = -100
        let url = try #require(await model.export())
        #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false))); #expect(model.alertMessage == nil)
        try FileManager.default.removeItem(at: dir.appending(path: "OC_0001.JPG"))
        #expect(await model.export() == nil); #expect(model.phase == .failed("This photo could not be opened."))
    }
}

// OpenCamTests/LastCaptureTests.swift
@MainActor @Suite struct LastCaptureTests {
    @Test func refreshDropsADeletedLastCapture() throws {
        let dir = try TestFiles.directory()
        try Data("x".utf8).write(to: dir.appending(path: "OC_0001.HEIC")); try Data("x".utf8).write(to: dir.appending(path: "OC_0002.JPG"))
        let model = CameraModel(config: LaunchConfig(), capabilities: try Fixture.load(), isSimulator: true, defaults: try Fixture.freshDefaults(),
                                captureStore: try CaptureStore(directory: dir))
        model.loadLastCapture(); #expect(model.lastCapture.map(CaptureStore.clipKey(for:)) == "OC_0002.JPG")
        try FileManager.default.removeItem(at: dir.appending(path: "OC_0002.JPG"))
        model.refreshLastCapture(); #expect(model.lastCapture.map(CaptureStore.clipKey(for:)) == "OC_0001.HEIC")
        model.openLibrary(); #expect(model.isLibraryPresented)
    }
    @Test func latestCaptureCountsImportsAndSamples() {
        #expect(CaptureStore.latestCaptureName(["OC_0003.HEIC", "OC_0004.JPG", "OC_0005.json", "OC_0005.edit.json"]) == "OC_0004.JPG")
        #expect(CaptureStore.latestCaptureName(["OC_0006.DNG", "OC_0006.HEIC", "OC_0002.PNG"]) == "OC_0006.HEIC")
        #expect(CaptureStore.nextSequence(existingNames: ["OC_0003.HEIC", "OC_0009.edit.json", "IMG_7.JPG", "OC_.json"]) == 10)   // one shared parser
    }
}
```

- [ ] **Step 2: Run to see them fail** — `scripts/test.sh PhotoExporterTests`. Expected: `cannot find 'PhotoExporter' in scope`.
- [ ] **Step 3: Implement export, the share sheet and the Library item wiring.**
- [ ] **Step 4: Run every suite** — `scripts/test.sh`. Expected: `** TEST SUCCEEDED **`, camera core suites included.
- [ ] **Step 5: Screenshot and look**

```bash
export SHOT_DIR=docs/screenshots/e1
SHOT_FRESH=1 scripts/shot.sh e1-editor-export-v -orientation portrait -screen editor -seedSamples on
scripts/shot.sh e1-camera-library-item-h -orientation landscape -mode photo -seedSamples on
```

Pass when the editor toolbar shows "Done", "Reset all" and "Export"; the camera shot shows the Library item enabled in the strip with the scene sample (OC_0003.JPG) as its image, everything else as the camera core's `t11` shots.

- [ ] **Step 6: Commit**

```bash
git add OpenCam OpenCamTests docs/screenshots/e1
git commit -m "feat: export edited photos and open the library from the camera"
```

**Full E1 verification** (results go in the PR, with the screenshots):
- [ ] `scripts/test.sh` passes, every suite; paste the summary line.
- [ ] Every `e1-` screenshot from Tasks 5 to 9 exists in `docs/screenshots/e1/` and meets its pass line.
- [ ] Review Focus 1 to 5: the five pinned tests are named in the PR with their pass.
- [ ] By hand in the `OpenCam Dev` simulator (`SHOT_FRESH=1 scripts/shot.sh e1-start -orientation portrait -seedSamples on` to install, then drive it with the iOS Simulator tool or by hand): the strip's Library item opens Library; "Import" opens the system photo picker, two Simulator sample photos import and the alert reads "Imported 2 photos."; open one, move Exposure quickly from end to end (the picture follows without stalling), hold the picture for the original, double-tap "Exposure" to reset, "Done" returns to a grid whose thumbnail shows the edit; "Save as look" with an empty name keeps "Save" disabled and reads "Enter a name."; save "Test", rename it, duplicate it, delete it, and the photo keeps its edit; select two photos, "Apply look" then "Remove look"; "Delete" asks first and removes both originals; "Export" opens the share sheet and "Save to Files" writes `OC_000n-edited.JPG`, while Files shows Captures unchanged apart from `.edit.json` files.
- [ ] Clips by hand: copy any short `.mov` into the app's `Documents/Captures` as `OC_0099.MOV` (`cp clip.mov "$(xcrun simctl get_app_container <udid> local.opencam.app data)/Documents/Captures/OC_0099.MOV"`), reopen Library: the clip comes first with a play badge and its duration, a tap plays it in the system preview, "Apply look" over it and one photo reads "Applied to 1 photo. 1 video was skipped.", and Select mode deletes it. Screenshot `e1-library-clip-v` with `SHOT_DIR=docs/screenshots/e1 scripts/shot.sh e1-library-clip-v -orientation portrait -screen library`.
- [ ] `Documents/Captures` in the simulator's app container (`xcrun simctl get_app_container <udid> local.opencam.app data`) holds only originals and `.edit.json` files; `Documents/Looks` holds one JSON per look.

**On the device:**
- [ ] A 48 MP RAW + HEIF capture appears as one item; it opens with the HEIC; sliders follow the finger without visible lag; export of the 48 MP photo completes and opens in Photos at full size.
- [ ] A DNG-only capture opens through the system RAW decode and its thumbnail matches the editor.
- [ ] A recorded clip appears in Library with the duration from its sidecar, plays in the system preview, and deleting it removes the MOV and its `.json` sidecar.
- [ ] Open phone (inner display): the editor puts the picture beside the 320 pt panel (regular width).
- [ ] A Display P3 photo of saturated colour (a red flower, a blue sky): with no edit, the editor, the thumbnail and the export look the same as Photos shows the original, with no clipping.
