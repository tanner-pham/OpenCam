# OpenCam Looks in the Camera, Part E2, Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Choose a saved look in the camera (None or a look), see it in the viewfinder, and have it applied to what the camera saves: baked into HEIF, kept beside an untouched DNG for RAW, preview only for video.

**Architecture:** One `LookStore` is made in `OpenCamApp` and shared by the camera, the Library and the editor. `CameraModel` holds the selected look as a copy (`CameraLook`), saved with the other selections and reconciled with the looks list whenever the Library closes. With None nothing new runs: the preview layer, the session's outputs and the capture path are today's. With a look, the Simulator draws its stand-in through `LookRenderer.renderColourAndVignette`; the device adds a video data output whose frames go through the same entry point to a Metal view; photo capture writes the photo exactly as today, then a `@concurrent` step bakes the look over the saved HEIF at full size with one atomic write, or writes an edit file beside a RAW-only DNG. Every new failure falls back to today's behaviour with a plain notice.

**Tech Stack:** Swift 6, SwiftUI, AVFoundation (`AVCaptureVideoDataOutput`, `AVCaptureDevice.RotationCoordinator`), Core Image (`CIContext.heifRepresentation`, `render(_:to:commandBuffer:bounds:colorSpace:)`), MetalKit (`MTKView`), ImageIO, Swift Testing, Xcode 27.2, `xcodebuild`, `simctl`.

**Spec:** `docs/superpowers/specs/2026-11-10-opencam-editor-looks-design.md`, sections "Where a look applies", "One renderer", "Order of work" row E2 and "Calls made without Tanner". This plan is `docs/superpowers/plans/2026-11-10-opencam-looks-in-camera-e2.md`. E1's interfaces come from `docs/superpowers/plans/2026-11-10-opencam-editor-looks-e1.md` as built on `feat/editor-looks`. API facts come only from `docs/research/capture-apis.md`, `docs/research/duo-layout-apis.md`, or a grep of `$(xcrun --sdk iphoneos --show-sdk-path)`; never from memory.

## Global Constraints

Every constraint of the camera core plan applies unchanged:

- "iPhone Duo only, iOS 27.1 or later, Xcode 27.2, Swift 6, SwiftUI." Deployment target `27.1`, `SWIFT_VERSION = 6.0`, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `SWIFT_APPROACHABLE_CONCURRENCY = YES` (both already set). Targets `OpenCam` (`local.opencam.app`) and `OpenCamTests` (Swift Testing), file-system-synchronized groups, so new files need no project edits. All paths are relative to the repo root.
- "No third-party dependencies." "SwiftUI with system components and system glass throughout; dark appearance only." All four interface orientations. `Theme` (`OpenCam/UI/Theme.swift`) for spacing and accent.
- Anti-goals, verbatim from the camera core: "A control that names a format or tool the device cannot actually use at that moment." "Imitation blur or glass drawn by hand where a system material exists." From the spec: "An edit that cannot be undone back to the original file." "A look that renders differently in the viewfinder, in the saved file and in the editor. One renderer serves all three." "A control for a tool that is not built yet."
- Simulator: tests and screenshots use only `OpenCam Dev` (`com.apple.CoreSimulator.SimDeviceType.iPhone-Duo`, `com.apple.CoreSimulator.SimRuntime.iOS-27-2-iPhone19-4`) by UDID through `scripts/sim-udid.sh`. Never `booted`, never another simulator.
- Code: no force unwraps, force casts or `try!` (tests included); no `Any`-typed values in our APIs; one type per file; errors are specific enums conforming to `Error, CustomStringConvertible` with messages `[Module:Function] Description — {context}`, and every `path:` in an error is `url.path(percentEncoded: false)` of the URL the caller passed; no `@preconcurrency import`, no `nonisolated(unsafe)`, no new `@unchecked Sendable`.
- Copy: plain, factual, sentence case, no em dashes in UI strings, no marketing or AI words, nothing named that is not built. Error descriptions are only logged (`Logger(subsystem: "local.opencam.app", category: <type>)`), never shown.
- Git: conventional commits, no attribution lines, never force-push.

Carried from E1 unchanged: `LookRenderer.shared` owns the only `CIContext` and every rendered picture is Display P3; capture files are matched by `CaptureStore.clipKey(for:)`, never URL equality; camera notices go only through `CameraModel.show(_:from:)` / `clearNotice(from:)`; an `.edit.json` is `<stem>.edit.json` beside its original, and originals are never rewritten.

Added by this plan:

- Branch: `feat/looks-in-camera`, stacked on `feat/editor-looks`. Every name below is as it is in that tree.
- Risk rule: with no look selected ("None") the camera behaves exactly as today. `SessionConfiguration.needsFrames` is false, so no data output is attached; `PhotoCaptureDelegate` writes as today; `LookCapture` is never called; `ViewfinderArea` draws today's views. Everything new is reached only through a selected look, and every new failure falls back to today's behaviour with a plain notice. A photo is never lost to a look.
- Isolation: `CameraLook`, `LookAvailability`, `LookBaker`, `LookCapture`, `FramePipeline`, `FrameSlot`, `FrameOrientation`, `FrameWatch` and `FrameFit` are `nonisolated` and `Sendable` (`FramePipeline` like `PhotoCaptureDelegate`: a `final class` with a `Mutex`). Baking is a `@concurrent` function; frames are handled on the pipeline's own serial queue. Only `CameraModel` and views are main-actor. No pixel buffer leaves the sample-buffer callback: it becomes a `CIImage` there (`CIImage` is `NS_SWIFT_SENDABLE` in the SDK), so no new `@unchecked Sendable` is needed. `PreviewSource` stays the one existing unchecked crossing and only gains the `Sendable` `FramePipeline`; the data output's connection is touched only inside `CameraSession.apply`, never from the main actor.
- JPEG: `PhotoFormat` has no JPEG yet, so "baked into HEIF or JPEG" means HEIF here; JPEG takes the same path when the format is added.
- Notices: a new `NoticeSource.look` for the look's own notices ("Look turned off. Looks need Rec. 709 or P3." and "The look cannot be shown in the viewfinder with this format."). The capture notices ("Look not applied. The photo was saved without it." and "Look not saved with the photo.") come from `.capture`, and a `PhotoSaveReport` notice always wins over them.
- Exact UI copy, used verbatim: row title "Look"; chip "None"; "Looks need Rec. 709 or P3."; "Shown in the viewfinder only. Video is recorded without it."; "Look turned off. Looks need Rec. 709 or P3."; "The look cannot be shown in the viewfinder with this format."; "Look not applied. The photo was saved without it."; "Look not saved with the photo."; the Simulator caption "No camera in Simulator" stays.
- Launch flag: `-cameraLook <name>` selects the look of that name at launch (with `-seedLook on` in the Simulator) and makes the launch scripted, so it neither restores nor saves selections.
- Screenshots: `SHOT_DIR=docs/screenshots/e2`, names prefixed `e2-`, display 1, through `scripts/shot.sh` (unchanged). The implementer reads every PNG.
- Device SDK compile (needed wherever AVFoundation or MetalKit code changes): `xcodebuild -project OpenCam.xcodeproj -scheme OpenCam -sdk iphoneos -destination generic/platform=iOS -derivedDataPath .build CODE_SIGNING_ALLOWED=NO build`, expected `** BUILD SUCCEEDED **`.
- Calls made in this plan (each small): (1) `LookStore` is a stateless value type with no change signal, so sharing one store does not by itself bring a new look into the camera; the camera reads the looks again when the Library closes (every look change happens under the Library cover) and at launch. (2) The camera writes the photo as it does today and the look is baked over the saved HEIF afterwards, in the model's capture task, by a `@concurrent` step and one atomic write. The photo is on disk before any rendering starts, so a failed bake, a crash or a kill cannot lose it, and the photo output's callback queue and the session actor are never blocked by a 48 MP render. (3) The look name in the summary is cut in the model to 16 characters (15 and "…"), because `FormatButton` is `.fixedSize()` and a frame cannot truncate it there. (4) A viewfinder fallback detaches the data output until the next lens, mode, format or look change, which tries again. (5) In video mode the summary drops the look's name while the viewfinder cannot show it, since the look then applies nowhere. (6) The data output asks for preview-sized buffers (`automaticallyConfiguresOutputBufferDimensions = false`, `deliversPreviewSizedOutputBuffers = true`, AVCaptureVideoDataOutput.h:244-266); the pipeline always turns the image itself by the angle from the rotation coordinator, because setting the angle on a data output's connection physically rotates buffers and needs a lengthy pipeline reconfiguration (AVCaptureSession.h:1085); only mirroring is set on the connection, inside `CameraSession.apply`. (7) The Look row sits after the chip rows and before the data-rate footer; a `-screen record` launch with `-cameraLook` opens Record settings scrolled to it, so the landscape screenshot shows it.

## Review Focus

1. A selected look deleted in the editor must become None without a crash and without a stale name in the summary. Pinned by `CameraLookTests.deletedLookBecomesNoneAndARenamedLookTakesItsNewName` (Task 1) and `LookRuleTests.deletedLookLeavesNoNameInTheSummary` (Task 2).
2. A baking failure must still save the photo. Pinned by `LookCaptureTests.bakingFailureStillSavesThePhoto` (Task 4).
3. With None selected the session configuration must be identical to today's, with no data output. Pinned by `FrameRuleTests.noLookMeansTodaysConfiguration` (Task 5).
4. A look must never be applied twice to the same picture: a RAW + HEIF pair bakes the HEIF and writes no edit file. Pinned by `LookCaptureTests.rawPlusHEIFBakesTheHEIFAndWritesNoEditFile` (Task 4).
5. Changing lens, mode or format while a look is on must keep the viewfinder and the selection consistent, or turn the look off with its notice. Pinned by `LookRuleTests.changingToHLGTurnsTheLookOffWithItsNotice` (Task 2) and `FrameRuleTests.lensModeAndFormatChangesKeepTheViewfinderConsistent` (Task 5).

---

### Task 1: One shared look store and the camera's look selection

**Files:**
- Create: `OpenCam/Edit/CameraLook.swift`, `OpenCam/App/CameraModel+Look.swift`
- Modify: `OpenCam/Support/SavedSelections.swift` (`var look: CameraLook? = nil`; the memberwise init and old saved JSON without `look` keep working), `OpenCam/App/LaunchConfig.swift` (`var cameraLookName: String?`, from `-cameraLook <name>`, sets `isScripted`; the doc comment's flag list gains it), `OpenCam/App/CameraModel.swift` (stored `var looks: [Look] = []`, `var cameraLook: CameraLook?` (set only by the look extension), `@ObservationIgnored let lookStore: LookStore?`; `init` gains a last parameter `lookStore: LookStore? = nil`; `selectionChanged()` drops `private` so the extension can call it; `currentSelection` passes `look: cameraLook`; `init` sets `cameraLook = saved?.look`, then `looks = lookStore?.all() ?? []`, `cameraLook = CameraLook.reconciled(cameraLook, with: looks)`, then for `config.cameraLookName` the look of that name, or None when there is none), `OpenCam/App/CameraModel+Library.swift` (`returnCameraFromLibrary()` calls `reloadLooks()` straight after its first guard (`guard !isLibraryPresented else { return }`), so the looks are read again on every path and before the selection is configured again; a look deleted in the Library is then None before any configure runs. The `defer { refreshLastCapture() }` stays as it is), `OpenCam/App/OpenCamApp.swift` (creates one `LookStore.appDefault()` in `init`, seeds "Warm fade" into it in the Simulator when `seedsLook`, both before `CameraModel` is constructed so a `-cameraLook` launch finds the look, passes it to `makeLibrary(captures:looks:config:)` and to `CameraModel(..., lookStore:)`; a store that fails is logged, the Library is then unavailable as today and the camera has only None)
- Test: `OpenCamTests/CameraLookTests.swift`; Modify `OpenCamTests/LaunchConfigTests.swift`

**Interfaces:**
- Consumes: E1 `Look`, `LookStore` (`all()`, `save`, `rename`, `delete`), `Adjustments`, `LookSeeder.warmFade`, `LookSeeder.warmFadeName`; camera core `SavedSelections`, `CameraModel.persist()`, `closeLibrary()`, `openLibrary()`.
- Produces:

```swift
nonisolated struct CameraLook: Codable, Sendable, Equatable {
    let id: UUID
    var name: String
    var adjustments: Adjustments
    init(id: UUID, name: String, adjustments: Adjustments)
    init(_ look: Look)
    /// nil when `selected` is nil or no look in `looks` has its id; otherwise that look's current name and adjustments.
    static func reconciled(_ selected: CameraLook?, with looks: [Look]) -> CameraLook?
}
extension CameraModel {
    func selectLook(_ id: UUID?)   // nil, or an id not in `looks`, is None; then selectionChanged()
    func reloadLooks()             // looks = lookStore?.all() ?? []; cameraLook reconciled; selectionChanged() only when cameraLook changed
}
// CameraModel.init(config:capabilities:isSimulator:defaults:capabilitySource:captureStore:isLibraryAvailable:lookStore:)
// LaunchConfig.cameraLookName: String?   SavedSelections.look: CameraLook?
```

- [ ] **Step 1: Write the failing tests**

```swift
// OpenCamTests/CameraLookTests.swift
import Foundation
import Testing
@testable import OpenCam

@MainActor @Suite struct CameraLookTests {
    let warm = Adjustments().setting(.temperature, to: 20)
    let cool = Adjustments().setting(.temperature, to: -20)

    func make(_ defaults: UserDefaults, _ looks: LookStore?, _ args: [String] = []) throws -> CameraModel {
        CameraModel(config: args.isEmpty ? LaunchConfig() : .parse(["app"] + args), capabilities: try Fixture.load(), isSimulator: true,
                    defaults: defaults, lookStore: looks)
    }

    @Test func noneByDefaultAndTheChoiceSurvivesARelaunch() throws {
        let defaults = try Fixture.freshDefaults(), looks = try LookStore(directory: TestFiles.directory())
        let look = try looks.save(name: "Warm fade", adjustments: warm)
        let first = try make(defaults, looks)
        #expect(first.cameraLook == nil); #expect(first.looks.map(\.id) == [look.id])
        first.selectLook(look.id)
        #expect(first.cameraLook == CameraLook(look))
        let second = try make(defaults, looks)
        #expect(second.cameraLook == CameraLook(look)); #expect(SavedSelections.load(from: defaults)?.look?.id == look.id)
        second.selectLook(nil)
        #expect(try make(defaults, looks).cameraLook == nil)
        second.selectLook(UUID()); #expect(second.cameraLook == nil)
    }

    @Test func deletedLookBecomesNoneAndARenamedLookTakesItsNewName() throws {   // Review Focus 1
        let defaults = try Fixture.freshDefaults(), looks = try LookStore(directory: TestFiles.directory())
        let a = try looks.save(name: "Warm fade", adjustments: warm), b = try looks.save(name: "Cool", adjustments: cool)
        let model = try make(defaults, looks)
        model.selectLook(a.id)
        _ = try looks.rename(a.id, to: "Warm"); model.reloadLooks()
        #expect(model.cameraLook == CameraLook(id: a.id, name: "Warm", adjustments: warm))
        #expect(SavedSelections.load(from: defaults)?.look?.name == "Warm")
        try looks.delete(a.id); model.reloadLooks()
        #expect(model.cameraLook == nil); #expect(model.looks.map(\.id) == [b.id]); #expect(SavedSelections.load(from: defaults)?.look == nil)
        model.selectLook(b.id); try looks.delete(b.id)
        #expect(try make(defaults, looks).cameraLook == nil)            // gone before the next launch
        #expect(try make(defaults, nil).cameraLook == nil)              // no look store at all
    }

    @Test func reconciledTakesTheLooksCurrentValues() {
        let id = UUID(), now = Date.now
        let selected = CameraLook(id: id, name: "Warm fade", adjustments: warm)
        #expect(CameraLook.reconciled(selected, with: [Look(id: id, name: "Warm fade", adjustments: cool, createdAt: now)])
                == CameraLook(id: id, name: "Warm fade", adjustments: cool))
        #expect(CameraLook.reconciled(selected, with: [Look(id: UUID(), name: "Warm fade", adjustments: warm, createdAt: now)]) == nil)
        #expect(CameraLook.reconciled(nil, with: []) == nil)
    }

    @Test func closingTheLibraryReadsTheLooksAgain() async throws {
        let looks = try LookStore(directory: TestFiles.directory())
        let a = try looks.save(name: "Warm fade", adjustments: warm)
        let model = try make(try Fixture.freshDefaults(), looks)
        model.selectLook(a.id); model.openLibrary()
        let added = try looks.save(name: "Agfa", adjustments: cool); try looks.delete(a.id)
        model.isLibraryPresented = false
        await model.closeLibrary()
        #expect(model.cameraLook == nil); #expect(model.looks.map(\.id) == [added.id])
    }

    @Test func scriptedLaunchSelectsByNameAndNeitherRestoresNorSaves() throws {
        let defaults = try Fixture.freshDefaults(), looks = try LookStore(directory: TestFiles.directory())
        let a = try looks.save(name: "Warm fade", adjustments: warm), b = try looks.save(name: "Cool", adjustments: cool)
        try make(defaults, looks).selectLook(b.id)
        let scripted = try make(defaults, looks, ["-cameraLook", "Warm fade"])
        #expect(scripted.cameraLook?.id == a.id)
        scripted.selectLook(nil)
        #expect(SavedSelections.load(from: defaults)?.look?.id == b.id)
        #expect(try make(defaults, looks, ["-mode", "photo"]).cameraLook == nil)
        #expect(try make(defaults, looks, ["-cameraLook", "Missing"]).cameraLook == nil)
    }

    @Test func savedSelectionsWithoutALookStillDecode() throws {
        let defaults = try Fixture.freshDefaults()
        let old = SavedSelections(mode: .photo, lensID: "wide", record: RecordSelection(family: .hevc, quality: "High", resolution: .named(width: 3840, height: 2160), frameRate: 30, colour: .rec709),
                                  photo: PhotoSelection(format: .heif, megapixels: 12))
        old.save(to: defaults)
        #expect(SavedSelections.load(from: defaults) == old); #expect(SavedSelections.load(from: defaults)?.look == nil)
    }
}

// Added to LaunchConfigTests
@Test func parsesCameraLookFlag() {
    let c = LaunchConfig.parse(["app", "-cameraLook", "Warm fade", "-seedLook", "on"])
    #expect(c.cameraLookName == "Warm fade"); #expect(c.isScripted)
    #expect(LaunchConfig.parse(["app", "-cameraLook", "Warm fade"]).isScripted)   // the flag alone makes the launch scripted
    #expect(LaunchConfig.parse(["app"]).cameraLookName == nil)
}
```

- [ ] **Step 2: Run to see them fail** — `scripts/test.sh CameraLookTests`. Expected: build error `cannot find 'CameraLook' in scope`.
- [ ] **Step 3: Implement the Interfaces and the Files edits.** `OpenCamApp` keeps one store for the whole run: `makeLibrary` no longer calls `LookStore.appDefault()` itself, and `EditorScreen` already uses `library.lookStore`, so the editor, the Library and the camera share it.
- [ ] **Step 4: Run to see them pass** — `scripts/test.sh CameraLookTests && scripts/test.sh LaunchConfigTests && scripts/test.sh SavedSelectionsTests && scripts/test.sh LibraryHandoffTests`. Expected: `** TEST SUCCEEDED **` four times.
- [ ] **Step 5: Commit**

```bash
git add OpenCam OpenCamTests
git commit -m "feat: share one look store and keep the camera's look selection"
```

---

### Task 2: The Look row, its availability, and the look name in the summary

**Files:**
- Create: `OpenCam/Capability/LookAvailability.swift`
- Modify: `OpenCam/App/NoticeSource.swift` (`case look`: "A look turned off or not shown in the viewfinder; cleared when a look is chosen or the viewfinder can show it again."), `OpenCam/App/CameraModel.swift` (`hasCamera` drops `private`; `selectionChanged()` calls `settleLook()` before `persist()`; `init` turns a restored or scripted look the current mode cannot take into None without a notice; `summaryParts` appends `summaryLookName` when it is non-nil; `@ObservationIgnored let scrollsToLookRow: Bool`, true when `config.screen == .record && config.cameraLookName != nil`), `OpenCam/App/CameraModel+Look.swift`, `OpenCam/UI/ChipRow.swift` (`var isSingleLine = false`, declared before `onSelect`: one horizontally scrolling line of chips instead of the grid, `columns` ignored (the Look row passes `columns: 1`); each chip at least `2 * Theme.Size.minTarget` wide and at most `Theme.Size.lookChipMax = 160`, title cut to one line with an ellipsis), `OpenCam/UI/ChipButton.swift` (`var isSingleLine = false`, passed from `ChipRow`; the title takes `.lineLimit(1)` only when it is true, other rows are unchanged), `OpenCam/UI/Theme.swift` (`Size.lookChipMax`), `OpenCam/UI/VideoRecordRows.swift` and `OpenCam/UI/PhotoRows.swift` (gain `let look: LookChoice` and draw `ChipRow(title: "Look", columns: 1, ..., isSingleLine: true)` after the last chip row and before the footer (`PhotoRows` has no footer: the row goes last there); with `look.scrollsIntoView` a `ScrollViewReader` scrolls to it on appear), `OpenCam/UI/RecordSettingsSheet.swift` (gains `let look: LookChoice`, passed to both), `OpenCam/UI/CameraRootView.swift` (builds `LookChoice` from the model), `OpenCam/UI/FormatButton.swift` (`ForEach(Array(parts.enumerated()), id: \.offset)`, so a look named like a format part never collides)
- Create: `OpenCam/UI/LookChoice.swift`
- Test: `OpenCamTests/LookAvailabilityTests.swift`, `OpenCamTests/LookRuleTests.swift`

**Interfaces:**
- Consumes: Task 1 `CameraLook`, `CameraModel.cameraLook`, `looks`, `selectLook(_:)`, `selectionChanged()`; camera core `Chip`, `ChipRow`, `ColourMode`, `CaptureMode`, `show(_:from:)`, `clearNotice(from:)`; `reloadLooks()` (Task 1).
- Produces:

```swift
nonisolated enum LookAvailability {
    static let noneID = "none"
    static let needsSDR = "Looks need Rec. 709 or P3."
    static let videoPreviewOnly = "Shown in the viewfinder only. Video is recorded without it."
    static let turnedOff = "Look turned off. Looks need Rec. 709 or P3."
    static let summaryNameLimit = 16
    static func isOffered(mode: CaptureMode, colour: ColourMode) -> Bool     // photo always; video only .rec709 and .p3
    static func chips(looks: [Look], isOffered: Bool) -> [Chip]             // "None" (id noneID) first, then each look (id uuidString, title name);
                                                                            // not offered: looks unavailable with reason needsSDR
    static func reasonLine(mode: CaptureMode, isOffered: Bool, hasLook: Bool) -> String?   // !isOffered: needsSDR; video with a look: videoPreviewOnly
    static func summaryName(_ name: String) -> String                       // <= 16 characters unchanged; else the first 15 and "…"
}
struct LookChoice { let chips: [Chip]; let selectedID: String; let reason: String?; let scrollsIntoView: Bool; let onSelect: (String) -> Void }
extension CameraModel {
    var isLookOffered: Bool { get }        // LookAvailability.isOffered(mode: mode, colour: record.colour)
    var lookChips: [Chip] { get }
    var lookChipID: String { get }         // cameraLook?.id.uuidString ?? LookAvailability.noneID
    var lookReason: String? { get }
    func selectLook(chipID: String)        // noneID -> selectLook(nil); a uuid -> selectLook(id); selecting a look clears the .look notice
    var summaryLookName: String? { get }   // nil without hasCamera or without a look; else LookAvailability.summaryName(cameraLook.name)
    func settleLook()                      // a look while !isLookOffered becomes None and shows LookAvailability.turnedOff from .look
}
```

- [ ] **Step 1: Write the failing tests**

```swift
// OpenCamTests/LookAvailabilityTests.swift
@Suite struct LookAvailabilityTests {
    let agfa = Look(id: UUID(), name: "Agfa", adjustments: Adjustments(), createdAt: .now)
    let warm = Look(id: UUID(), name: "Warm fade", adjustments: Adjustments().setting(.temperature, to: 20), createdAt: .now)

    @Test func offeredForRec709AndP3InVideoAndAlwaysInPhoto() {
        #expect(LookAvailability.isOffered(mode: .video, colour: .rec709)); #expect(LookAvailability.isOffered(mode: .video, colour: .p3))
        for colour in [ColourMode.hlg, .appleLog, .appleLog2] { #expect(!LookAvailability.isOffered(mode: .video, colour: colour)) }
        for colour in ColourMode.allCases { #expect(LookAvailability.isOffered(mode: .photo, colour: colour)) }
    }
    @Test func chipsPutNoneFirstAndDimLooksWhenNotOffered() {
        let chips = LookAvailability.chips(looks: [agfa, warm], isOffered: true)
        #expect(chips.map(\.title) == ["None", "Agfa", "Warm fade"]); #expect(chips.map(\.id) == ["none", agfa.id.uuidString, warm.id.uuidString])
        #expect(chips.allSatisfy(\.isAvailable))
        let dimmed = LookAvailability.chips(looks: [agfa, warm], isOffered: false)
        #expect(dimmed.map(\.isAvailable) == [true, false, false]); #expect(dimmed[2].reason == "Looks need Rec. 709 or P3.")
        #expect(LookAvailability.chips(looks: [], isOffered: true).map(\.title) == ["None"])
    }
    @Test func reasonLinesAndSummaryNames() {
        #expect(LookAvailability.reasonLine(mode: .video, isOffered: true, hasLook: true) == "Shown in the viewfinder only. Video is recorded without it.")
        #expect(LookAvailability.reasonLine(mode: .video, isOffered: true, hasLook: false) == nil)
        #expect(LookAvailability.reasonLine(mode: .video, isOffered: false, hasLook: false) == "Looks need Rec. 709 or P3.")
        #expect(LookAvailability.reasonLine(mode: .photo, isOffered: true, hasLook: true) == nil)
        #expect(LookAvailability.summaryName("Warm fade") == "Warm fade"); #expect(LookAvailability.summaryName("Sixteen chars ok") == "Sixteen chars ok")
        #expect(LookAvailability.summaryName("A very long look name") == "A very long loo…")
    }
}

// OpenCamTests/LookRuleTests.swift
@MainActor @Suite struct LookRuleTests {
    let uhd = Resolution.named(width: 3840, height: 2160)

    func make() throws -> (CameraModel, LookStore, Look) {
        let looks = try LookStore(directory: TestFiles.directory())
        let look = try looks.save(name: "Warm fade", adjustments: Adjustments().setting(.temperature, to: 20))
        let model = CameraModel(config: LaunchConfig(), capabilities: try Fixture.load(), isSimulator: true, defaults: try Fixture.freshDefaults(), lookStore: looks)
        return (model, looks, look)
    }

    @Test func changingToHLGTurnsTheLookOffWithItsNotice() throws {   // Review Focus 5
        let (model, _, look) = try make()
        model.mode = .video
        model.record = RecordSelection(family: .proRes, quality: "422 HQ", resolution: uhd, frameRate: 30, colour: .rec709)
        model.selectLook(look.id)
        #expect(model.lookReason == "Shown in the viewfinder only. Video is recorded without it."); #expect(model.summaryParts.last == "Warm fade")
        model.record = RecordSelection(family: .proRes, quality: "422 HQ", resolution: uhd, frameRate: 30, colour: .hlg)
        #expect(model.currentVideoOption?.colour == .hlg)
        #expect(model.cameraLook == nil); #expect(model.notice == "Look turned off. Looks need Rec. 709 or P3.")
        #expect(model.lookChipID == "none"); #expect(model.lookChips.dropFirst().allSatisfy { !$0.isAvailable })
        #expect(model.lookReason == "Looks need Rec. 709 or P3."); #expect(model.summaryParts == ["ProRes", "4K", "HLG"])
        model.mode = .photo
        model.selectLook(chipID: look.id.uuidString)
        #expect(model.cameraLook?.id == look.id); #expect(model.notice == nil); #expect(model.lookReason == nil)
        model.mode = .video
        #expect(model.cameraLook == nil); #expect(model.notice == "Look turned off. Looks need Rec. 709 or P3.")
    }

    @Test func deletedLookLeavesNoNameInTheSummary() throws {   // Review Focus 1
        let (model, looks, look) = try make()
        model.mode = .photo; model.selectLook(look.id)
        #expect(model.summaryParts == ["RAW + HEIF", "48 MP", "Warm fade"])
        try looks.delete(look.id); model.reloadLooks()
        #expect(model.summaryLookName == nil); #expect(model.summaryParts == ["RAW + HEIF", "48 MP"]); #expect(model.lookChips.map(\.title) == ["None"])
    }

    @Test func noCameraPictureNamesNoLook() throws {
        let looks = try LookStore(directory: TestFiles.directory())
        _ = try looks.save(name: "Warm fade", adjustments: Adjustments().setting(.temperature, to: 20))
        let scanning = CameraModel(config: .parse(["app", "-state", "scanning", "-cameraLook", "Warm fade"]), capabilities: try Fixture.load(),
                                   isSimulator: true, defaults: try Fixture.freshDefaults(), lookStore: looks)
        #expect(scanning.cameraLook != nil); #expect(scanning.summaryLookName == nil); #expect(scanning.summaryParts == ["--"])
    }
}
```

- [ ] **Step 2: Run to see them fail** — `scripts/test.sh LookAvailabilityTests`. Expected: `cannot find 'LookAvailability' in scope`.
- [ ] **Step 3: Implement the Interfaces and the Files edits.** `settleLook()` runs inside `selectionChanged()` after its `isApplyingSelection` guard and sets `cameraLook` directly, so it never re-enters `selectionChanged()`. `configureFailed` calls `settleLook()` after restoring the selection, then `persist()` (a look failing back to an HLG last-working selection becomes None); no new test, as there is no fake configurator to make a configure fail.
- [ ] **Step 4: Run to see them pass** — `scripts/test.sh LookAvailabilityTests && scripts/test.sh LookRuleTests && scripts/test.sh CameraModelTests`. Expected: `** TEST SUCCEEDED **` three times (the summary tests of the camera core are unchanged with None).
- [ ] **Step 5: Screenshot and look**

```bash
export SHOT_DIR=docs/screenshots/e2
SHOT_FRESH=1 scripts/shot.sh e2-settings-photo-v -orientation portrait -mode photo -screen record -seedLook on -cameraLook "Warm fade"
scripts/shot.sh e2-settings-photo-h -orientation landscape -mode photo -screen record -seedLook on -cameraLook "Warm fade"
scripts/shot.sh e2-settings-video-v -orientation portrait -mode video -screen record -seedLook on -cameraLook "Warm fade"
scripts/shot.sh e2-settings-video-h -orientation landscape -mode video -screen record -seedLook on -cameraLook "Warm fade"
```

Pass when: each sheet shows a "Look" row after the last existing row, one line of chips, "None" first and "Warm fade" prominent in the accent colour; the video shots show "Shown in the viewfinder only. Video is recorded without it." under the row, the photo shots no reason line; the landscape video shot is scrolled so the Look row is fully visible; the data-rate footer still follows in video; nothing clipped or wrapped, every other row as in the camera core's baseline shots in `docs/screenshots/p1a/` (`t4-record-photo-v`, `-video-v`, `-video-h`; compare `e2-settings-photo-h` against the video-h layout, as there is no photo-h baseline).

- [ ] **Step 6: Commit**

```bash
git add OpenCam OpenCamTests docs/screenshots/e2
git commit -m "feat: choose a look in record settings and name it in the summary"
```

---

### Task 3: The look in the Simulator's stand-in viewfinder

**Files:**
- Create: `OpenCam/UI/StandInPicture.swift`, `OpenCam/UI/LookStandIn.swift`, `OpenCam/UI/StandInCaption.swift` (the "No camera in Simulator" capsule, moved out of `ViewfinderStandIn` unchanged and used by both)
- Modify: `OpenCam/UI/ViewfinderStandIn.swift` (uses `StandInCaption`; drawing unchanged), `OpenCam/UI/ViewfinderArea.swift` (`var look: CameraLook? = nil`; `.simulator` draws `LookStandIn(look: look, captionTopInset:)`), `OpenCam/UI/FoldedHorizontalView.swift`, `OpenCam/UI/FoldedVerticalView.swift`, `OpenCam/UI/FoldedVerticalVideoView.swift` (pass `look: model.viewfinderLook`), `OpenCam/App/CameraModel+Look.swift`
- Test: `OpenCamTests/StandInLookTests.swift`

**Interfaces:**
- Consumes: Task 1 `CameraLook`; Task 2 `isLookOffered`; E1 `LookRenderer.shared.renderColourAndVignette(_:cube:vignette:)`, `LookRenderer.shared.cgImage(_:)`, `LookCompiler.cube(for:)`, `LookSeeder.warmFade`.
- Produces:

```swift
@MainActor enum StandInPicture {
    static func base(size: CGSize, scale: CGFloat) -> CGImage?          // ImageRenderer of ViewfinderStandIn(showsCaption: false), as SampleSeeder does
    nonisolated @concurrent static func looked(_ base: CGImage, look: CameraLook) async -> CGImage?
        // renderColourAndVignette(CIImage(cgImage: base), cube: LookCompiler.cube(for: look.adjustments), vignette: look.adjustments.vignette)
}
struct LookStandIn: View { let look: CameraLook?; var captionTopInset: CGFloat = 0 }
    // nil: ViewfinderStandIn(captionTopInset:) exactly as today. A look: the stand-in rendered once per size and look
    // (.task(id:) keyed on size, scale and look), drawn filling the area, with StandInCaption on top; the plain stand-in shows until the image is ready.
extension CameraModel {
    var viewfinderLook: CameraLook? { get }   // cameraLook while isLookOffered; Task 5 adds the frame fallback
}
```

- [ ] **Step 1: Write the failing test**

```swift
@MainActor @Suite struct StandInLookTests {
    @Test func warmFadeWarmsTheStandInAtTheSameSize() async throws {
        let plain = try #require(StandInPicture.base(size: CGSize(width: 200, height: 300), scale: 1))
        let look = CameraLook(id: UUID(), name: "Warm fade", adjustments: LookSeeder.warmFade)
        let looked = try #require(await StandInPicture.looked(plain, look: look))
        #expect(looked.width == plain.width); #expect(looked.height == plain.height)
        #expect(looked.colorSpace?.name == CGColorSpace.displayP3)
        // Core Image rows count from the bottom: y 250 is the blue sky near the top.
        let p = try PixelReader.rgb(CIImage(cgImage: plain), x: 100, y: 250), l = try PixelReader.rgb(CIImage(cgImage: looked), x: 100, y: 250)
        #expect(l.x - l.z > p.x - p.z + 0.03)
    }
    @Test func viewfinderLookFollowsTheSelection() throws {
        let looks = try LookStore(directory: TestFiles.directory())
        let look = try looks.save(name: "Warm fade", adjustments: LookSeeder.warmFade)
        let model = CameraModel(config: LaunchConfig(), capabilities: try Fixture.load(), isSimulator: true, defaults: try Fixture.freshDefaults(), lookStore: looks)
        #expect(model.viewfinderLook == nil)
        model.selectLook(look.id); #expect(model.viewfinderLook == CameraLook(look))
        model.selectLook(nil); #expect(model.viewfinderLook == nil)
    }
}
```

- [ ] **Step 2: Run to see it fail** — `scripts/test.sh StandInLookTests`. Expected: `cannot find 'StandInPicture' in scope`.
- [ ] **Step 3: Implement the Interfaces and the Files edits.** The image is drawn with `Image(decorative:scale:)` at the environment's `displayScale`, and `base` is called with that scale.
- [ ] **Step 4: Run to see it pass** — `scripts/test.sh StandInLookTests`. Expected: `** TEST SUCCEEDED **`.
- [ ] **Step 5: Screenshot and look**

```bash
export SHOT_DIR=docs/screenshots/e2
SHOT_FRESH=1 scripts/shot.sh e2-camera-none-photo-v -orientation portrait -mode photo -seedLook on
for o in portrait landscape; do s=${o:0:1}; [[ $s == p ]] && s=v || s=h
  scripts/shot.sh "e2-camera-look-photo-$s" -orientation "$o" -mode photo -seedLook on -cameraLook "Warm fade"
  scripts/shot.sh "e2-camera-look-video-$s" -orientation "$o" -mode video -seedLook on -cameraLook "Warm fade"
done
```

Pass when: `e2-camera-none-photo-v` matches the camera core's photo shot and its summary has no look name; in the four look shots the stand-in is visibly warmer and flatter with darker corners than `e2-camera-none-photo-v`, "No camera in Simulator" still shows in its capsule, the summary ends with "Warm fade" (stacked as one more line in portrait photo), and no other part of the summary or bar is pushed out or clipped, and the picture keeps its full width on the folded display; if the third summary line makes it shrink, say so in the report.

- [ ] **Step 6: Commit**

```bash
git add OpenCam OpenCamTests docs/screenshots/e2
git commit -m "feat: show the selected look on the simulator viewfinder"
```

---

### Task 4: Baking the look at capture

**Files:**
- Create: `OpenCam/Render/LookBaker.swift`, `OpenCam/Render/LookBakeError.swift`, `OpenCam/Capture/LookCapture.swift`, `OpenCam/Capture/LookCaptureOutcome.swift`
- Modify: `OpenCam/App/CameraModel.swift` (`capturePhoto()` reads `let look = cameraLook` at the press; with a look it awaits `LookCapture.finish` on the session's result inside the same `photoCaptures[sequence]` task, so a configure, a rescan or the Library's release waits for the bake; `photoFinished(requested:result:lookNotice:)` shows the `PhotoSaveReport` notice when there is one, else `lookNotice`, else clears `.capture`. With None every call is today's and `LookCapture` is never reached). The model makes the `EditStore` for `finish` as `EditStore(directory: store.directory)` from its capture store, as `OpenCamApp.swift` does. `OpenCam/Render/PhotoExporter.swift` is not changed; `carriedMetadata(from:size:)` is reused.
- NOT modified: `PhotoCaptureDelegate`, `PhotoCapturer`, `CameraSession`, `PhotoCaptureResult`. The camera writes the photo exactly as it does today, look or no look.
- Test: `OpenCamTests/LookBakerTests.swift`, `OpenCamTests/LookCaptureTests.swift`

**Interfaces:**
- Consumes: Task 1 `CameraLook`; E1 `LookRenderer.render(_:adjustments:)`, `LookRenderer.displayP3`, `PhotoExporter.carriedMetadata(from: [String: Any], size: CGSize)`, `EditStore`, `PhotoEdit`; camera core `PhotoCaptureResult`, `PhotoFormat`, `PhotoSaveReport`.
- Produces:

```swift
nonisolated enum LookBakeError: Error, CustomStringConvertible, Equatable { case undecodable, encodeFailed }
    // "[LookBaker:bake] Photo data could not be decoded — {bytes: N}" / "[LookBaker:bake] The baked photo could not be encoded — {width: W, height: H}"
nonisolated enum LookBaker {
    static let quality = 0.9
    /// Decodes upright (CIImage(data:options: [.applyOrientationProperty: true])), renders the full pipeline at full size,
    /// and encodes HEIF (context.heifRepresentation, .RGBA8, Display P3, quality 0.9) with PhotoExporter's carried metadata.
    static func bake(_ data: Data, adjustments: Adjustments, renderer: LookRenderer = .shared) throws(LookBakeError) -> Data
}
nonisolated struct LookCaptureOutcome: Sendable, Equatable { let result: PhotoCaptureResult; let notice: String? }
nonisolated enum LookCapture {
    static let lookNotApplied = "Look not applied. The photo was saved without it."
    static let lookNotSaved = "Look not saved with the photo."
    @concurrent static func finish(_ result: PhotoCaptureResult, look: CameraLook, format: PhotoFormat, heicURL: URL, dngURL: URL,
                                   edits: EditStore, renderer: LookRenderer = .shared) async -> LookCaptureOutcome
}
```

`finish` rules. The `result` is returned unchanged in every case; only the notice differs.
(a) When `heicURL` is in `result.saved` (formats `.heif` and `.rawPlusHEIF`): read the file's bytes, bake them, and replace the file with the baked bytes by one atomic write (`Data.write(to:options: .atomic)`). The photo the camera wrote is on disk the whole time, so a failed bake, a crash or a kill during the bake cannot lose it. If reading, baking or the replacing write fails, the file stays as the camera wrote it, the failure is logged and the notice is `lookNotApplied`.
(b) Only for `.raw` with `dngURL` in `saved`: `edits.save(PhotoEdit(adjustments: look.adjustments, lookName: look.name), stem:)` with the stem `dngURL.deletingPathExtension().lastPathComponent`; a failure is logged and the notice is `lookNotSaved`.
(c) `.rawPlusHEIF` and `.heif` never write an edit file, and a `.rawPlusHEIF` capture whose HEIF was not saved gets neither a bake nor an edit file (the save report already says what was saved). The DNG is never opened. A result without the file its format needs in `saved` comes back unchanged with no notice.

- [ ] **Step 1: Write the failing tests**

```swift
// OpenCamTests/LookBakerTests.swift
@Suite struct LookBakerTests {
    @Test func bakedHEIFIsUprightDisplayP3WithTheLookAndTheMetadata() throws {
        let url = try TestFiles.directory().appending(path: "source.HEIC")
        let exif: [CFString: Any] = [kCGImagePropertyExifDateTimeOriginal: "2026:11:10 09:30:00"]
        let tiff: [CFString: Any] = [kCGImagePropertyTIFFMake: "Apple", kCGImagePropertyTIFFModel: "iPhone Duo"]
        _ = try TestFiles.writeOrientedPicture(width: 400, height: 300, orientation: 6, type: .heic,
                                               metadata: [kCGImagePropertyExifDictionary: exif, kCGImagePropertyTIFFDictionary: tiff], to: url)
        let baked = try LookBaker.bake(try Data(contentsOf: url), adjustments: Adjustments().setting(.saturation, to: -100))
        let source = try #require(CGImageSourceCreateWithData(baked as CFData, nil))
        #expect(CGImageSourceGetType(source) as String? == UTType.heic.identifier)
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect((properties[kCGImagePropertyOrientation] as? Int ?? 1) == 1)
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == 300); #expect(properties[kCGImagePropertyPixelHeight] as? Int == 400)
        #expect((properties[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifDateTimeOriginal] as? String == "2026:11:10 09:30:00")
        #expect((properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFModel] as? String == "iPhone Duo")
        #expect(try #require(CGImageSourceCreateImageAtIndex(source, 0, nil)).colorSpace?.name == CGColorSpace.displayP3)
        // Upright, red was the top half; saturation -100 makes it grey.
        let top = try PixelReader.rgb(try #require(CIImage(data: baked)), x: 150, y: 300)
        #expect(abs(top.x - top.y) < 0.03); #expect(abs(top.x - top.z) < 0.03)
    }
    @Test func undecodableDataThrows() {
        #expect(throws: LookBakeError.undecodable) { try LookBaker.bake(Data("not a photo".utf8), adjustments: Adjustments()) }
    }
}

// OpenCamTests/LookCaptureTests.swift
@Suite struct LookCaptureTests {
    let look = CameraLook(id: UUID(), name: "Warm fade", adjustments: Adjustments().setting(.exposure, to: 1))

    func urls() throws -> (dir: URL, dng: URL, heic: URL) {
        let dir = try TestFiles.directory()
        return (dir, dir.appending(path: "OC_0001.DNG"), dir.appending(path: "OC_0001.HEIC"))
    }
    func grey() throws -> Data { try TestFiles.heicData(width: 400, height: 300, rgb: SIMD3(0.5, 0.5, 0.5)) }
    func centre(_ url: URL) throws -> Float { try PixelReader.rgb(PictureDecoder.full(at: url), x: 200, y: 150).x }
    func hasEditFile(_ dir: URL) -> Bool {
        FileManager.default.fileExists(atPath: EditStore(directory: dir).url(forStem: "OC_0001").path(percentEncoded: false))
    }

    @Test func heifWithALookIsBakedAndWritesNoEditFile() async throws {
        let (dir, dng, heic) = try urls()
        try grey().write(to: heic)                                   // the camera has already written the photo
        #expect(abs(try centre(heic) - 0.5) < 0.02)
        let saved = PhotoCaptureResult(saved: [heic], error: nil)
        let outcome = await LookCapture.finish(saved, look: look, format: .heif, heicURL: heic, dngURL: dng, edits: EditStore(directory: dir))
        #expect(outcome == LookCaptureOutcome(result: saved, notice: nil))
        #expect(abs(try centre(heic) - 0.686) < 0.02)
        #expect(!hasEditFile(dir))
    }
    @Test func bakingFailureStillSavesThePhoto() async throws {   // Review Focus 2
        let (dir, dng, heic) = try urls()
        let written = Data("not a photo".utf8); try written.write(to: heic)
        let saved = PhotoCaptureResult(saved: [heic], error: nil)
        let outcome = await LookCapture.finish(saved, look: look, format: .heif, heicURL: heic, dngURL: dng, edits: EditStore(directory: dir))
        #expect(outcome == LookCaptureOutcome(result: saved, notice: "Look not applied. The photo was saved without it."))
        #expect(try Data(contentsOf: heic) == written)               // the file the camera wrote is untouched
    }
    @Test func rawWritesAnEditFileBesideTheUntouchedDNG() async throws {
        let (dir, dng, heic) = try urls()
        let raw = Data("dng bytes".utf8); try raw.write(to: dng)
        let saved = PhotoCaptureResult(saved: [dng], error: nil)
        let outcome = await LookCapture.finish(saved, look: look, format: .raw, heicURL: heic, dngURL: dng, edits: EditStore(directory: dir))
        #expect(outcome == LookCaptureOutcome(result: saved, notice: nil))
        #expect(try EditStore(directory: dir).load(stem: "OC_0001") == PhotoEdit(adjustments: look.adjustments, lookName: "Warm fade"))
        #expect(try Data(contentsOf: dng) == raw)
    }
    @Test func rawPlusHEIFBakesTheHEIFAndWritesNoEditFile() async throws {   // Review Focus 4
        let (dir, dng, heic) = try urls()
        let raw = Data("dng bytes".utf8); try raw.write(to: dng); try grey().write(to: heic)
        let saved = PhotoCaptureResult(saved: [dng, heic], error: nil)
        let outcome = await LookCapture.finish(saved, look: look, format: .rawPlusHEIF, heicURL: heic, dngURL: dng, edits: EditStore(directory: dir))
        #expect(outcome == LookCaptureOutcome(result: saved, notice: nil))
        #expect(abs(try centre(heic) - 0.686) < 0.02); #expect(try Data(contentsOf: dng) == raw)
        #expect(!hasEditFile(dir))
    }
    @Test func rawPlusHEIFWithoutItsHEIFGetsNeitherABakeNorAnEditFile() async throws {
        let (dir, dng, heic) = try urls()
        let raw = Data("dng bytes".utf8); try raw.write(to: dng)
        let partial = PhotoCaptureResult(saved: [dng], error: .noPhotoData)
        let outcome = await LookCapture.finish(partial, look: look, format: .rawPlusHEIF, heicURL: heic, dngURL: dng, edits: EditStore(directory: dir))
        #expect(outcome == LookCaptureOutcome(result: partial, notice: nil))
        #expect(!hasEditFile(dir)); #expect(try Data(contentsOf: dng) == raw)
        #expect(!FileManager.default.fileExists(atPath: heic.path(percentEncoded: false)))
    }
    @Test func editFileFailureKeepsTheDNG() async throws {
        let (dir, dng, heic) = try urls()
        try Data("dng bytes".utf8).write(to: dng)
        let saved = PhotoCaptureResult(saved: [dng], error: nil)
        let outcome = await LookCapture.finish(saved, look: look, format: .raw, heicURL: heic, dngURL: dng,
                                               edits: EditStore(directory: dir.appending(path: "missing", directoryHint: .isDirectory)))
        #expect(outcome == LookCaptureOutcome(result: saved, notice: "Look not saved with the photo."))
        #expect(FileManager.default.fileExists(atPath: dng.path(percentEncoded: false)))
    }
    @Test func failedCapturesAreLeftAsTheyAre() async throws {
        let (dir, dng, heic) = try urls()
        let failed = PhotoCaptureResult(saved: [], error: .noPhotoData)
        for format in [PhotoFormat.heif, .raw, .rawPlusHEIF] {
            #expect(await LookCapture.finish(failed, look: look, format: format, heicURL: heic, dngURL: dng, edits: EditStore(directory: dir))
                    == LookCaptureOutcome(result: failed, notice: nil))
        }
        #expect(!hasEditFile(dir))
    }
}
```

If `PhotoCaptureError` has no `.noPhotoData` case or `PhotoCaptureResult` is not `Equatable` as written, use the existing case and comparison the camera core's `PhotoCaptureTests` use; never weaken what is compared.

- [ ] **Step 2: Run to see them fail** — `scripts/test.sh LookBakerTests`. Expected: `cannot find 'LookBaker' in scope`.
- [ ] **Step 3: Implement `LookBaker`, `LookCapture` and the model's edits to the Interfaces.** Add one model test to `LookCaptureTests` or the camera core's capture tests, using the tests' existing fake configurator: with a look selected a HEIF capture's notice is the save report's when there is one, else the look's, else none; with None `photoFinished` behaves as today. The camera core's `PhotoCaptureTests` and `PhotoSaveReportTests` must pass untouched.
- [ ] **Step 4: Run to see them pass** — `scripts/test.sh LookBakerTests && scripts/test.sh LookCaptureTests && scripts/test.sh PhotoCaptureTests && scripts/test.sh PhotoSaveReportTests`, then the device SDK compile from Global Constraints. Expected: `** TEST SUCCEEDED **` four times, then `** BUILD SUCCEEDED **`.
- [ ] **Step 5: Commit**

```bash
git add OpenCam OpenCamTests
git commit -m "feat: bake the selected look into captured photos"
```

---

### Task 5: The look on the device's viewfinder

> **Revised after Task 5 was built (ruling in the ledger):** the data output's connection is made neutral once, inside `CameraSession.apply` during configuration (`videoRotationAngle = 0` when supported; `automaticallyAdjustsVideoMirroring = false` and `isVideoMirrored = false` when mirroring is supported), so buffers always arrive in the sensor's own orientation, unmirrored. The pipeline turns the image and then mirrors it for a front camera. `FrameOrientation.plan(angle:isFront:)` returns only `imageRotation` and `imageMirrors`; `FramePipeline.setCamera(isFront:)`; the test is `thePipelineTurnsTheImageThenMirrorsItForAFrontCamera`. Where the text below still says the connection mirrors, this note wins. Reasons: a mirror on the connection followed by a turn in the image is 180 degrees off the preview at 90 and 270, and AVCaptureSession.h says some devices give front-camera video data a default angle of 180 and recommends setting 0.

**Files:**
- Create in `OpenCam/Capture/`: `FramePipeline.swift`, `FrameSlot.swift`, `FrameOrientation.swift`, `FrameWatch.swift`, `FrameFit.swift`; Create `OpenCam/App/CameraModel+Frames.swift`, `OpenCam/UI/FrameView.swift` (`UIViewRepresentable`), `OpenCam/UI/FrameMetalView.swift` (`MTKView` subclass)
- Modify: `OpenCam/Capture/SessionConfiguration.swift` (`var needsFrames = false`; `make` gains `needsFrames: Bool = false`), `OpenCam/Capture/SessionEvent.swift` (`case framesUnavailable`: the data output could not be added; the viewfinder keeps the preview layer), `OpenCam/Capture/PreviewSource.swift` (`let frames: FramePipeline`; the doc comment says the pipeline is `Sendable` and adds nothing to the unchecked crossing), `OpenCam/Capture/CameraSession.swift` (owns `let frames = FramePipeline()` and one `AVCaptureVideoDataOutput` with `alwaysDiscardsLateVideoFrames = true`, `automaticallyConfiguresOutputBufferDimensions = false`, `deliversPreviewSizedOutputBuffers = true`, delegate `frames` on `frames.queue`; `apply(_:)` calls `attachFrameOutput(configuration.needsFrames)` after `attachMovieOutput`, inside the same `beginConfiguration`/`commitConfiguration`; with the output attached it sets `automaticallyAdjustsVideoMirroring = false` and `isVideoMirrored` (true for a front camera, read from `position` at runtime) on the data output's connection when `isVideoMirroringSupported`, and tells the pipeline through `frames.setCamera(isFront:connectionCanMirror:)`; the connection's rotation angle is never set; with `needsFrames` false it removes the output if attached, so a None configuration leaves today's outputs; when it cannot be added it does not throw, it yields `.framesUnavailable` and the configure stands), `OpenCam/UI/PreviewUIView.swift` (split: the `didConfigureNotification` observer always calls a new `applyFrameOrientation()`, which passes `rotationCoordinator?.videoRotationAngleForHorizonLevelPreview` to `source.frames.setAngle(_:)`, then `updateRotationCoordinator()`, so the coordinator is still rebuilt only for a new camera; `applyRotation(_:)` calls it too. It never reads `session.outputs` and never touches the data output's connection, and with no data output in `session.outputs` nothing changes), `OpenCam/UI/ViewfinderArea.swift` (`.ready`: `CameraPreviewView` and `FrameView` sit in a `ZStack` in both cases, so turning a look on or off never rebuilds the preview; with a look, `FrameView` is on top and the preview takes `.opacity(0)` once the first frame is drawn; with None, `FrameView` is absent and the preview shows at once), `OpenCam/App/CameraModel.swift` (`sessionConfiguration` passes `needsFrames: needsFrames`; `selectionChanged()` sets `isLookViewfinderUnavailable = false` and clears the `.look` notice before `settleLook()`; `enqueueConfigure`'s success path, `start(session:)` after `session.start()`, and `returnCameraFromLibrary()` after `configurator.start()` call `watchFrames(for: configuration)`, so a stalled look at launch or after the Library gets its notice; `apply(_:)` maps `.framesUnavailable` to `framesUnavailable()`; stored `var isLookViewfinderUnavailable = false`, `@ObservationIgnored var frameWatch: Task<Void, Never>?`), `OpenCam/App/CameraModel+Look.swift` (`viewfinderLook` is also nil while `isLookViewfinderUnavailable`; `summaryLookName` is nil in video mode while it is)
- Test: `OpenCamTests/FrameRuleTests.swift`, `OpenCamTests/FramePartsTests.swift`

**Interfaces:**
- Consumes: Task 1 `CameraLook`; Task 2 `isLookOffered`, `settleLook()`, `NoticeSource.look`; Task 3 `viewfinderLook`; E1 `LookRenderer.renderColourAndVignette(_:cube:vignette:)`, `ColourCubeCache`, `LookRenderer.context`, `displayP3`; camera core `FakeSessionConfigurator`, `attachSession`, `applySelection()`, `PreviewUIView`'s rotation coordinator.
- Produces:

```swift
nonisolated struct FrameSlot<Frame: Sendable>: Sendable {
    private(set) var dropped = 0
    mutating func put(_ frame: Frame)          // replaces an undrawn frame, counting it in dropped
    mutating func take() -> Frame?             // the newest frame once; nil until another arrives
}
nonisolated struct FrameOrientation: Sendable, Equatable {
    var connectionMirrors: Bool                // isVideoMirrored on the connection, set inside CameraSession.apply (automaticallyAdjustsVideoMirroring = false first)
    var imageRotation: CGImagePropertyOrientation   // always applied by the pipeline: .up, or .right/.down/.left for 90/180/270; the connection's angle is never set
    var imageMirrors: Bool                     // the pipeline flips horizontally after rotating
    static func plan(angle: CGFloat, isFront: Bool, connectionCanMirror: Bool) -> FrameOrientation
}
nonisolated enum FrameWatch {
    static let timeout: Duration = .seconds(2)
    static func isStalled(framesSinceConfigure: Int, elapsed: Duration) -> Bool   // no frame and elapsed >= timeout
}
nonisolated enum FrameFit {
    static func aspectFit(_ extent: CGRect, in drawable: CGSize) -> CGAffineTransform   // as .resizeAspect: scaled to fit, centred
}
nonisolated final class FramePipeline: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, Sendable {
    let queue: DispatchSerialQueue             // "opencam.frames"
    init(renderer: LookRenderer = .shared)
    func setLook(_ adjustments: Adjustments?)  // the table comes from its own ColourCubeCache on the frame queue, built once per look
    func setAngle(_ angle: CGFloat)            // from PreviewUIView's rotation coordinator; the pipeline applies FrameOrientation.plan
    func setCamera(isFront: Bool, connectionCanMirror: Bool)   // from CameraSession.apply
    func takeLatest() -> CIImage?
    var deliveredCount: Int { get }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection)
        // pixel buffer -> CIImage -> remaining rotation and mirror -> renderColourAndVignette -> slot; nothing kept without a look
}
final class FrameMetalView: MTKView { init(frames: FramePipeline, onFirstFrame: @escaping () -> Void) }
    // MTLCreateSystemDefaultDevice(), framebufferOnly = false, `(layer as? CAMetalLayer)?.colorspace` set to Display P3, colorPixelFormat `.bgra8Unorm` (8-bit, the same depth as the editor's proxy preview); each draw takes frames.takeLatest()
    // and returns early when there is none; renders through LookRenderer.shared.context into the drawable with FrameFit.
struct FrameView: UIViewRepresentable { let frames: FramePipeline; let look: CameraLook; let onFirstFrame: () -> Void }
    // calls frames.setLook(look.adjustments) when made and when the look changes; dismantleUIView calls frames.setLook(nil), which empties the slot
extension CameraModel {
    static let framesUnavailableNotice = "The look cannot be shown in the viewfinder with this format."
    var needsFrames: Bool { get }           // cameraLook != nil && isLookOffered && !isLookViewfinderUnavailable
    func framesUnavailable()                // isLookViewfinderUnavailable = true, notice from .look, enqueueConfigure(); the look stays
    func watchFrames(for configuration: SessionConfiguration)   // needsFrames and a running cameraSession only: cancels the last watch,
        // reads frames.deliveredCount, sleeps FrameWatch.timeout, then framesUnavailable() if isStalled and the look is still on
}
```

The `plan` table the tests pin: front cameras (`AVCaptureDevice.position == .front`, read at runtime) are mirrored, back cameras never; mirroring goes on the connection when it supports it, else to the image; the image is always turned by the angle (0, 90, 180, 270 to `.up`, `.right`, `.down`, `.left`), because setting the angle on a data output's connection physically rotates buffers and needs a lengthy capture pipeline reconfiguration (AVCaptureSession.h:1085). The rotation coordinator is the preview layer's, whose preview angle stays valid because the hidden layer remains in the view hierarchy (AVCaptureDevice.h:3117).

- [ ] **Step 1: Write the failing tests**

```swift
// OpenCamTests/FrameRuleTests.swift
@MainActor @Suite struct FrameRuleTests {
    let uhd = Resolution.named(width: 3840, height: 2160)

    func make() throws -> (CameraModel, Look) {
        let looks = try LookStore(directory: TestFiles.directory())
        let look = try looks.save(name: "Warm fade", adjustments: Adjustments().setting(.temperature, to: 20))
        let model = CameraModel(config: LaunchConfig(), capabilities: try Fixture.load(), isSimulator: false, defaults: try Fixture.freshDefaults(), lookStore: looks)
        model.phase = .ready
        return (model, look)
    }

    @Test func noLookMeansTodaysConfiguration() async throws {   // Review Focus 3
        let (model, look) = try make()
        let lens = try #require(model.currentLens)
        let today = SessionConfiguration.make(lens: lens, mode: model.mode, video: model.currentVideoOption, photo: model.currentPhotoOption, access: model.access)
        #expect(model.sessionConfiguration == today); #expect(today.needsFrames == false)
        let fake = FakeSessionConfigurator(failingLensIDs: [])
        model.attachSession(fake, configuredWith: today, selection: model.currentSelection)
        model.selectLook(look.id); try await model.applySelection()
        model.selectLook(nil); try await model.applySelection()
        #expect(await fake.applied.map(\.needsFrames) == [true, false])
        #expect(await fake.applied.last == today)
    }

    @Test func lensModeAndFormatChangesKeepTheViewfinderConsistent() throws {   // Review Focus 5
        let (model, look) = try make()
        model.mode = .video
        model.record = RecordSelection(family: .proRes, quality: "422 HQ", resolution: uhd, frameRate: 30, colour: .rec709)
        model.selectLook(look.id)
        model.selectLens("ultraWide")
        #expect(model.cameraLook?.id == look.id); #expect(model.viewfinderLook?.id == look.id); #expect(model.sessionConfiguration?.needsFrames == true)
        model.mode = .photo
        #expect(model.viewfinderLook?.id == look.id); #expect(model.sessionConfiguration?.needsFrames == true)

        model.apply(.framesUnavailable)
        #expect(model.cameraLook?.id == look.id); #expect(model.viewfinderLook == nil); #expect(model.sessionConfiguration?.needsFrames == false)
        #expect(model.notice == "The look cannot be shown in the viewfinder with this format."); #expect(model.summaryLookName == "Warm fade")
        model.mode = .video
        #expect(model.notice == nil); #expect(model.sessionConfiguration?.needsFrames == true)   // a new format tries again
        model.framesUnavailable()
        #expect(model.summaryLookName == nil)                                                    // video: the look applies nowhere
        model.record = RecordSelection(family: .proRes, quality: "422 HQ", resolution: uhd, frameRate: 30, colour: .appleLog)
        #expect(model.cameraLook == nil); #expect(model.notice == "Look turned off. Looks need Rec. 709 or P3.")
        #expect(model.sessionConfiguration?.needsFrames == false)
    }
}

// OpenCamTests/FramePartsTests.swift
@Suite struct FramePartsTests {
    @Test func slotKeepsOnlyTheNewestFrame() {
        var slot = FrameSlot<Int>()
        #expect(slot.take() == nil)
        slot.put(1); slot.put(2); slot.put(3)
        #expect(slot.take() == 3); #expect(slot.take() == nil); #expect(slot.dropped == 2)
        slot.put(4); #expect(slot.take() == 4); #expect(slot.dropped == 2)
    }
    @Test func theImageIsAlwaysTurnedByThePipelineAndMirroredOnTheConnectionWhenItCan() {
        #expect(FrameOrientation.plan(angle: 90, isFront: false, connectionCanMirror: true)
                == FrameOrientation(connectionMirrors: false, imageRotation: .right, imageMirrors: false))
        #expect(FrameOrientation.plan(angle: 90, isFront: true, connectionCanMirror: true)
                == FrameOrientation(connectionMirrors: true, imageRotation: .right, imageMirrors: false))
        #expect(FrameOrientation.plan(angle: 90, isFront: true, connectionCanMirror: false)
                == FrameOrientation(connectionMirrors: false, imageRotation: .right, imageMirrors: true))
        #expect(FrameOrientation.plan(angle: 180, isFront: false, connectionCanMirror: false).imageRotation == .down)
        #expect(FrameOrientation.plan(angle: 270, isFront: false, connectionCanMirror: false).imageRotation == .left)
        #expect(FrameOrientation.plan(angle: 0, isFront: false, connectionCanMirror: false).imageRotation == .up)
    }
    @Test func watchStallsOnlyAfterTwoSecondsWithoutAFrame() {
        #expect(!FrameWatch.isStalled(framesSinceConfigure: 0, elapsed: .milliseconds(1900)))
        #expect(FrameWatch.isStalled(framesSinceConfigure: 0, elapsed: .seconds(2)))
        #expect(!FrameWatch.isStalled(framesSinceConfigure: 1, elapsed: .seconds(5)))
    }
    @Test func aspectFitCentresTheFrame() {
        let fitted = CGRect(x: 0, y: 0, width: 1920, height: 1080).applying(FrameFit.aspectFit(CGRect(x: 0, y: 0, width: 1920, height: 1080), in: CGSize(width: 1000, height: 1000)))
        #expect(abs(fitted.minX) < 0.001); #expect(abs(fitted.width - 1000) < 0.001)
        #expect(abs(fitted.minY - 218.75) < 0.001); #expect(abs(fitted.height - 562.5) < 0.001)
    }
}
```

- [ ] **Step 2: Run to see them fail** — `scripts/test.sh FramePartsTests`. Expected: `cannot find 'FrameSlot' in scope`.
- [ ] **Step 3: Implement the Interfaces and the Files edits.** `FramePipeline` keeps a `Mutex` state (look adjustments, orientation, `FrameSlot<CIImage>`, delivered count) and a `ColourCubeCache` of its own, so the editor's one-entry cache is never pushed out by the viewfinder.
- [ ] **Step 4: Run to see them pass** — `scripts/test.sh FrameRuleTests && scripts/test.sh FramePartsTests && scripts/test.sh SessionConfigurationTests`, then the device SDK compile. Expected: `** TEST SUCCEEDED **` three times, then `** BUILD SUCCEEDED **`.
- [ ] **Step 5: Check the Simulator path is unchanged** — `SHOT_DIR=docs/screenshots/e2 scripts/shot.sh e2-camera-look-photo-v -orientation portrait -mode photo -seedLook on -cameraLook "Warm fade"` and `git diff --stat docs/screenshots/e2`. Pass when the new shot looks the same as Task 3's (the stand-in path does not touch frames); if it differs only by the clock, keep Task 3's file with `git checkout docs/screenshots/e2`.
- [ ] **Step 6: Commit**

```bash
git add OpenCam OpenCamTests
git commit -m "feat: draw camera frames through the selected look on the device"
```

**On the device** (owner, Task 6 collects it): the checklist in Task 6.

---

### Task 6: Honest states and E2 verification

**Files:**
- Modify: whatever the sweep below finds; no new behaviour.
- Test: `OpenCamTests/LookHonestyTests.swift`

**Interfaces:**
- Consumes: everything above.
- Produces: nothing new.

- [ ] **Step 1: Write the failing test** (it fails only if an earlier task left a dishonest state; if it passes at once, record that in the PR and go on)

```swift
@MainActor @Suite struct LookHonestyTests {
    @Test func theLookIsNamedOnlyWhereItApplies() throws {
        let looks = try LookStore(directory: TestFiles.directory())
        let look = try looks.save(name: "Warm fade", adjustments: LookSeeder.warmFade)
        let model = CameraModel(config: LaunchConfig(), capabilities: try Fixture.load(), isSimulator: true, defaults: try Fixture.freshDefaults(), lookStore: looks)
        #expect(model.lookChipID == "none"); #expect(model.summaryLookName == nil); #expect(model.viewfinderLook == nil); #expect(!model.needsFrames)
        model.mode = .photo; model.selectLook(look.id)
        #expect(model.summaryLookName == "Warm fade"); #expect(model.lookReason == nil)
        model.framesUnavailable()
        #expect(model.summaryLookName == "Warm fade")          // photo: still applied at capture
        model.selectLook(nil)
        #expect(model.notice == nil); #expect(model.summaryLookName == nil); #expect(!model.needsFrames)
    }
}
```

- [ ] **Step 2: Run it** — `scripts/test.sh LookHonestyTests`. Expected: `** TEST SUCCEEDED **`, or a failure whose fix is the smallest change in the owning file.
- [ ] **Step 3: Sweep by reading** — each of these holds or is fixed: the Simulator caption reads "No camera in Simulator" with and without a look; every string in Global Constraints' copy list appears verbatim exactly where named (`grep -rn "Looks need Rec. 709 or P3." OpenCam` and the same for each other string), and no UI string added by this plan has an em dash; no UI names sharpening, noise reduction or grain for the viewfinder; `git diff feat/editor-looks -- OpenCam/Capture/PhotoCaptureDelegate.swift OpenCam/Capture/PhotoCapturer.swift OpenCam/Capture/PhotoCaptureResult.swift` is empty, and the same diff of `OpenCam/Capture/CameraSession.swift` shows only code reached when `needsFrames` is true. Carried from the task reviews, each fixed here with a test where one is named: (1) `settleLook()` must not replace a capture notice or the configuration notice ("That format could not be used."): it shows its own notice only when the current notice is absent or from `.look`; test `LookRuleTests.turningTheLookOffKeepsAFailedFormatNotice`. (2) A look whose adjustments are the identity is not baked (no lossy re-encode of an unchanged picture) and writes no edit file for RAW; test `LookCaptureTests.identityLookLeavesThePhotoAndWritesNothing`. (3) `LookBakeError`'s doc comment is reworded to say plainly that the cases carry no values and the context is logged by `LookCapture`. (4) `NoticeSource.look`'s doc comment matches what the code does.
- [ ] **Step 4: Run every suite** — `scripts/test.sh`. Expected: `** TEST SUCCEEDED **`, camera core and E1 suites included. Then the device SDK compile. Expected: `** BUILD SUCCEEDED **`.
- [ ] **Step 5: Commit**

```bash
git add OpenCam OpenCamTests
git commit -m "fix: keep look states honest across the camera"
```

**Full E2 verification** (results go in the PR, with the screenshots):
- [ ] `scripts/test.sh` passes, every suite; paste the summary line.
- [ ] The device SDK compile passes; paste `** BUILD SUCCEEDED **`.
- [ ] Every `e2-` screenshot from Tasks 2 and 3 exists in `docs/screenshots/e2/` and meets its pass line.
- [ ] Review Focus 1 to 5: the pinned tests are named in the PR with their pass.
- [ ] By hand in the `OpenCam Dev` simulator (`SHOT_FRESH=1 scripts/shot.sh e2-start -orientation portrait -mode photo -seedSamples on -seedLook on`, then relaunch without flags by hand so selections save): Record settings shows the Look row with None selected; choose "Warm fade", the stand-in warms and the summary gains "Warm fade"; open Library, open a photo, "Save as look" as "Test", return to the camera, and "Test" is in the Look row without a relaunch; rename "Warm fade" in the editor and the summary follows when the Library closes; delete it and the camera shows None with no name in the summary; switch to video, choose a look, change Colour to HLG, and the notice reads "Look turned off. Looks need Rec. 709 or P3."; quit and relaunch, and the last chosen look is still selected.

**On the device** (owner; the Simulator cannot show any of it):
- [ ] With None: the viewfinder, frame rate and photo capture feel exactly as before E2.
- [ ] Choose "Warm fade" (seeded in the Simulator only, so make a look in the editor first): the viewfinder shows the look within a moment, upright and level in all four orientations, the preview layer never shows through, and switching back to None shows the plain preview at once.
- [ ] The cameras that report `.front` show a mirrored look viewfinder, as the plain preview does; the others do not.
- [ ] Lens, mode and format changes with a look on keep the look in the viewfinder; a format that cannot take it shows "The look cannot be shown in the viewfinder with this format." and the plain preview, and the next lens or format change tries again.
- [ ] HEIF with a look: the saved `OC_000n.HEIC` shows the look, upright, in Display P3, with the camera's date and lens data, and matches the viewfinder and the editor's look tile by eye.
- [ ] RAW + HEIF with a look: the DNG opens without the look; the HEIC has it; Library shows one item with the look; no `.edit.json` beside them.
- [ ] RAW with a look: the DNG is untouched and `OC_000n.edit.json` names the look; Library and the editor show it with the look; "Remove look" returns the plain DNG.
- [ ] A 48 MP HEIF with a look: the next press is not blocked and a lens change waits for the bake without a frozen viewfinder; capture-to-thumbnail time noted in the PR.
- [ ] Video with a look: the clip plays back without the look; the viewfinder showed it while recording.
- [ ] Battery and heat: ten minutes with a look in the viewfinder against ten with None, noted in the PR (spec open risk 1).
