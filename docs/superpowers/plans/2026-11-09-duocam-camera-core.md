# DuoCam Camera Core (P1a) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A sideloaded SwiftUI camera app for the folded iPhone Duo that records every photo and movie-output video format the device reports, with honest Record settings, Camera Control, live readouts and an on-device format sweep that proves each combination.

**Architecture:** A plain-data capability model (`Capability/`, Foundation only) is built once per OS build by a thin AVFoundation scanner, cached as JSON, and drives every picker through pure resolvers. A `CameraSession` actor on its own serial executor owns `AVCaptureSession`, the photo output and the movie output; one `@Observable` `CameraModel` on the main actor joins capture events to the ported prototype views. Everything that can be pure is pure and unit-tested in the Simulator; everything that needs a camera has an "On the device" checklist.

**Tech Stack:** Swift 6, SwiftUI, AVFoundation, AVKit (Camera Control), CoreMedia, QuickLook, Swift Testing, Xcode 27.2, `xcodebuild`, `simctl`.

**Spec:** `docs/superpowers/specs/2026-11-09-duo-camera-design.md`. API facts come only from `docs/research/capture-apis.md`, `docs/research/duo-layout-apis.md`, or a grep of `$(xcrun --sdk iphoneos --show-sdk-path)`; never from memory.

## Global Constraints

- "iPhone Duo only, iOS 27.1 or later, Xcode 27.2, Swift 6, SwiftUI." Deployment target `27.1`, `SWIFT_VERSION = 6.0`, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (as the prototype). Every type in `DuoCam/Capability/` is `nonisolated`, `Sendable`, and imports Foundation only.
- Targets: app `DuoCam` (bundle id `local.duocam.app`) and unit tests `DuoCamTests` (`local.duocam.app.tests`, Swift Testing). `DuoCam.xcodeproj` at the repo root with file-system-synchronized groups. `TARGETED_DEVICE_FAMILY = 1`. Source folders `DuoCam/App`, `Capability`, `Capture`, `UI`, `Support`. All paths are relative to the repo root.
- "No third-party dependencies." "SwiftUI with system components and system glass throughout; dark appearance only." All four interface orientations.
- "The Simulator has no camera. Every capture path is verified on the physical Duo. UI is verified in the Duo simulator with a stand-in image." The stand-in reads `No camera in Simulator`.
- Outer display "466 x 678 pt at 3x"; the strip is "about 86 pt wide". Strip items are `ToolbarItem(placement: .bottomBar)` with `.axisBehavior(.verticalPreferred)`.
- Anti-goals, verbatim: "A control that names a format or tool the device cannot actually use at that moment." "Imitation blur or glass drawn by hand where a system material exists." "Controls covering the picture on the outer display when the strip or the letterbox bars could hold them." "A recording that drops frames without saying so."
- Captures: `Documents/Captures/` named `DC_0001.DNG`, `DC_0001.HEIC`, `DC_0002.MOV`, `DC_0002.json`; `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace` true. Storage reserve `2_000_000_000` bytes; GB means 10^9 bytes everywhere.
- Simulator: tests and screenshots use only the simulator `DuoCam Dev` (`com.apple.CoreSimulator.SimDeviceType.iPhone-Duo`, `com.apple.CoreSimulator.SimRuntime.iOS-27-2-iPhone19-4`) by UDID. Never `booted`, never another simulator.
- Code: no force unwraps, force casts or `try!` (tests included); no `Any`-typed values in our APIs (AVFoundation dictionaries are built at the call site from typed structs); one type per file; errors are specific enums conforming to `Error, CustomStringConvertible` with messages `[Module:Function] Description — {context}`, e.g. `[CameraSession:configure] Cannot add input — {lens: wide}`. The one unchecked crossing is `PreviewSource` (`@unchecked Sendable`), because `AVCaptureSession` is not Sendable in the SDK; no `@preconcurrency import`, no `nonisolated(unsafe)`.
- Copy: plain, factual, sentence case, no em dashes in UI strings, no marketing or AI words, no "Analyzing" or "Thinking" states, never name a format or tool the device cannot use at that moment (a dimmed chip with its reason is allowed, per the spec's Record settings section).
- Git: conventional commits, no attribution lines, never force-push.
- Deliberate spec deviations: (1) No Dolby Vision chip; colours are exactly what `supportedColorSpaces` reports, and Dolby Vision metadata on HLG is checked on the device first. (2) No running dropped-frame count while recording: the movie output has no per-frame callback. Dropped frames are computed after each clip, kept in its sidecar and shown as a notice; a later plan closes the gap. (3) The strip has four items (Mode, Lens, Record settings, Library); Monitor tools is left out until its plan lands. (4) The bottom bar's histogram slot is empty until the monitoring plan. (5) Readouts are live and read-only. (6) "RAW" video means ProRes RAW through the movie output, listed only when the device reports `aprn` or `aprh`. (7) The photo panel has Format and Resolution rows; the lens is chosen on the strip. (8) Combinations that failed the last format sweep stay selectable so every format can be tried, but Record settings then reads "This combination did not record in the last format sweep." and the format summary takes the warning style.

## Review Focus

1. A cached capability file from an older OS build must trigger a rescan. Pinned by `CapabilityCacheTests.olderOSBuildTriggersRescan` (Task 7).
2. Recording into nearly full storage must stop cleanly at the reserve and leave a playable file with its sidecar. Pinned by `RecordingOutcomeTests.diskFullStopsCleanlyAndKeepsPlayableFile` (Task 9) and the `-freeSpaceMarginMB` device check.
3. An interruption mid-recording (backgrounding, folding or unfolding, a phone call) must finalize the file and reset the UI. Pinned by `RecordingOutcomeTests.interruptionFinalizesFile` and `CameraModelRecordingTests.interruptionResetsUI` (Task 9).
4. Switching to a lens that cannot do the current selection must move to the nearest valid one without crashing. Pinned by `RecordSelectionResolverTests.lensWithoutSelectionMovesToNearestValid` and `.lensWithNoOptionsReturnsNil` (Task 2).
5. Microphone denied with camera allowed must still record video and say there is no sound. Pinned by `CaptureAccessTests.microphoneDeniedStillRecordsVideoWithoutSound` (Task 9) and `StatusTextTests.bottomNoticePrecedence` (Task 11).

---

### Task 1: Project, test script, capability model and fixture

**Files:**
- Create: `DuoCam.xcodeproj/project.pbxproj`, modelled on `prototype/DuoCamPrototype.xcodeproj/project.pbxproj` (objectVersion 77, `PBXFileSystemSynchronizedRootGroup`s `DuoCam` and `DuoCamTests`), plus a `bundle.unit-test` target with `TEST_HOST = $(BUILT_PRODUCTS_DIR)/DuoCam.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/DuoCam`, `BUNDLE_LOADER = $(TEST_HOST)` and a target dependency
- Create: `DuoCam.xcodeproj/xcshareddata/xcschemes/DuoCam.xcscheme` (builds DuoCam, tests DuoCamTests)
- Create: `Config/DuoCam-Info.plist`, a copy of `probe/Info-extra.plist`, outside the synchronized group so it is not copied as a resource (`INFOPLIST_FILE = Config/DuoCam-Info.plist`, `GENERATE_INFOPLIST_FILE = YES`)
- Create: `scripts/sim-udid.sh`, `scripts/test.sh`, `scripts/make-fixture/main.swift`, `DuoCam/App/DuoCamApp.swift` (black `WindowGroup`, replaced in Task 4)
- Create in `DuoCam/Capability/`: `CaptureCapabilities.swift`, `CapabilityError.swift`, `Lens.swift`, `LensKind.swift`, `VideoOption.swift`, `VideoCodec.swift`, `CodecFamily.swift`, `BitrateTier.swift`, `Resolution.swift`, `ColourMode.swift`, `PhotoOption.swift`, `PhotoFormat.swift`
- Create: `DuoCam/Support/CapabilitiesFixture.json` (generated)
- Test: `DuoCamTests/CaptureCapabilitiesTests.swift`, `DuoCamTests/Fixture.swift` (`enum Fixture { static func load() throws -> CaptureCapabilities; static func freshDefaults() throws -> UserDefaults }`, the second a new `UserDefaults(suiteName: UUID().uuidString)`; used by later suites)

Other build settings: `INFOPLIST_KEY_CFBundleDisplayName = DuoCam`, `INFOPLIST_KEY_UIUserInterfaceStyle = Dark`, `INFOPLIST_KEY_NSCameraUsageDescription = "Shows the camera picture and records photos and video."`, `INFOPLIST_KEY_NSMicrophoneUsageDescription = "Records sound with video."`, `CODE_SIGN_STYLE = Automatic`, `DEVELOPMENT_TEAM = ""` (the owner sets a team locally for device builds; never commit one).

**Interfaces:**
- Consumes: nothing.
- Produces (all `nonisolated`, `Codable, Sendable, Hashable` unless noted):

```swift
struct CaptureCapabilities: Codable, Sendable, Equatable {
    var lenses: [Lens]; var videoOptions: [VideoOption]; var photoOptions: [PhotoOption]; var osBuild: String; var modelIdentifier: String
    static func bundledFixture(in bundle: Bundle = .main) throws(CapabilityError) -> CaptureCapabilities   // "CapabilitiesFixture.json"
    static func decode(_ data: Data) throws(CapabilityError) -> CaptureCapabilities
    func encoded() throws(CapabilityError) -> Data                 // .prettyPrinted, .sortedKeys
    func videoOptions(forLens id: String) -> [VideoOption]; func photoOptions(forLens id: String) -> [PhotoOption]
}
enum CapabilityError: Error, CustomStringConvertible { case fixtureMissing, unreadable(path: String, reason: String), unwritable(path: String, reason: String) }
struct Lens: Identifiable { let id: String; let kind: LensKind; let deviceUniqueID: String; let zoomFactor: Double; let label: String }
enum LensKind: String { case ultraWide, wide, outerUltraWide, innerUltraWide }
struct VideoOption { let lensID: String; let codec: VideoCodec; let resolution: Resolution; let frameRate: Int; let colour: ColourMode }
struct VideoCodec { let family: CodecFamily; let quality: String; let codecType: String; let bitrateTier: BitrateTier?
    var displayName: String }     // raw: the quality ("ProRes RAW HQ"); else "ProRes 422 HQ", "HEVC Max", "H.264 High"
enum CodecFamily: String, CaseIterable { case raw, proRes, hevc, h264; var title: String }   // "RAW", "ProRes", "HEVC", "H.264"
enum BitrateTier: String, CaseIterable { case max = "Max", high = "High", medium = "Medium", low = "Low"; var bitsPerPixelPerFrame: Double }  // 0.18 0.11 0.07 0.04
struct Resolution { let width: Int; let height: Int; let label: String
    var id: String { get }; var detail: String { get }; var pixelCount: Int { get }   // "3840x2160", "3840 x 2160"
    static func named(width: Int, height: Int) -> Resolution }
enum ColourMode: String, CaseIterable { case rec709 = "Rec. 709", p3 = "P3", hlg = "HLG", appleLog = "Apple Log", appleLog2 = "Apple Log 2"
    init?(captureColorSpace rawValue: Int)    // 0 sRGB, 1 P3_D65, 2 HLG_BT2020, 3 AppleLog, 4 AppleLog2, in case order
    var shortName: String }                  // "Rec. 709", "P3", "HLG", "Log", "Log 2"
struct PhotoOption { let lensID: String; let format: PhotoFormat; let width: Int; let height: Int
    var megapixels: Int { get }; var label: String { get } }   // floor(w * h / 1_000_000); "48 MP"
enum PhotoFormat: String, CaseIterable { case raw = "RAW", rawPlusHEIF = "RAW + HEIF", heif = "HEIF"; var includesRAW: Bool }
```

`Resolution.named` labels: 3840x2160 "4K", 4096x2160 "4K DCI", 2704x1520 "2.7K", 1920x1080 "1080p", 1280x720 "720p", any 4:3 size "Open gate", else `detail`.

**Fixture** (`scripts/make-fixture/main.swift` builds exactly this; `osBuild` and `modelIdentifier` are `"fixture"`). Lenses in order: `ultraWide` (ultraWide, "0.5x", zoom 1), `wide` (wide, "1x", 1), `wide@2` (wide, "2x", 2), `outer` (outerUltraWide, "Outer front", 1), `inner` (innerUltraWide, "Inner front", 1). Video is every combination of each row:

| Lenses | Qualities (FourCC) | Resolution: rates | Colours |
|---|---|---|---|
| wide, wide@2 | ProRes 422 HQ `apch`, 422 `apcn`, 422 LT `apcs`, 422 Proxy `apco` | 4K: 24 25 30; 1080p: 24 25 30 48 50 60 | Rec. 709, HLG, Apple Log, Apple Log 2 |
| ultraWide | same ProRes | 1080p: 24 25 30 48 50 60 | same |
| wide, wide@2, ultraWide | HEVC `hvc1` Max, High, Medium, Low | 4K and 1080p: 24 25 30 48 50 60 | Rec. 709, HLG, Apple Log 2 |
| wide, wide@2, ultraWide | HEVC tiers | 1080p: 100 120 | Rec. 709 |
| wide, wide@2, ultraWide | H.264 `avc1` Max, High, Medium, Low | 4K: 24-60; 1080p: 24-60, 100, 120 | Rec. 709 |
| outer, inner | HEVC tiers | 1080p: 24 25 30 60 | Rec. 709, HLG |
| outer, inner | H.264 tiers | 1080p: 24 25 30 60 | Rec. 709 |

Photo: `wide` all three formats at 8064x6048 and 4032x3024; `ultraWide` all three at 4032x3024; `wide@2`, `outer`, `inner` HEIF at 4032x3024.

- [ ] **Step 1: Write the simulator scripts and check them**

```bash
#!/bin/zsh
# scripts/sim-udid.sh: prints the UDID of "DuoCam Dev", creating and booting it if needed
set -euo pipefail
NAME="DuoCam Dev"; TYPE=com.apple.CoreSimulator.SimDeviceType.iPhone-Duo; RUNTIME=com.apple.CoreSimulator.SimRuntime.iOS-27-2-iPhone19-4
UDID="$(xcrun simctl list devices | grep -E "^ +$NAME \(" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')"
if [[ -z "$UDID" ]]; then UDID="$(xcrun simctl create "$NAME" "$TYPE" "$RUNTIME")"; fi
xcrun simctl bootstatus "$UDID" -b >/dev/null
print -r -- "$UDID"
```

```bash
#!/bin/zsh
# scripts/test.sh [SuiteName]
set -euo pipefail
cd "$(dirname "$0")/.."
UDID="$(scripts/sim-udid.sh)"
xcodebuild test -quiet -project DuoCam.xcodeproj -scheme DuoCam -destination "id=$UDID" \
  -derivedDataPath .build CODE_SIGNING_ALLOWED=NO ${1:+-only-testing:DuoCamTests/$1}
```

Run: `chmod +x scripts/*.sh && scripts/sim-udid.sh && xcrun simctl list devices | grep -c "DuoCam Dev"` — Expected: a UDID, then `1`.

- [ ] **Step 2: Write the failing test**

```swift
@Suite struct CaptureCapabilitiesTests {
    @Test func fixtureLoadsWithExpectedCounts() throws {
        let caps = try CaptureCapabilities.bundledFixture()
        #expect(caps.lenses.map(\.id) == ["ultraWide", "wide", "wide@2", "outer", "inner"])
        #expect(caps.videoOptions(forLens: "wide").count == 352); #expect(caps.videoOptions(forLens: "ultraWide").count == 304)
        #expect(caps.videoOptions(forLens: "outer").count == 48); #expect(caps.photoOptions(forLens: "wide").count == 6)
        #expect(caps.photoOptions(forLens: "wide@2").map(\.format) == [.heif])
        #expect(Set(caps.videoOptions).count == caps.videoOptions.count)
    }
    @Test func codableRoundTripIsLossless() throws {
        let caps = try CaptureCapabilities.bundledFixture()
        #expect(try CaptureCapabilities.decode(caps.encoded()) == caps)
        #expect(throws: CapabilityError.self) { try CaptureCapabilities.decode(Data("{".utf8)) }
    }
    @Test func namesAndLabels() {
        #expect(Resolution.named(width: 3840, height: 2160).label == "4K"); #expect(Resolution.named(width: 4032, height: 3024).label == "Open gate")
        #expect(Resolution.named(width: 2000, height: 1000).label == "2000 x 1000")
        #expect(PhotoOption(lensID: "wide", format: .raw, width: 8064, height: 6048).label == "48 MP")
        #expect(ColourMode(captureColorSpace: 4) == .appleLog2); #expect(ColourMode(captureColorSpace: 9) == nil)
        #expect(VideoCodec(family: .proRes, quality: "422 HQ", codecType: "apch", bitrateTier: nil).displayName == "ProRes 422 HQ")
    }
}
```

- [ ] **Step 3: Run it to see it fail** — `scripts/test.sh CaptureCapabilitiesTests`. Expected: build error `cannot find 'CaptureCapabilities' in scope`.
- [ ] **Step 4: Implement the types in Interfaces, then generate the fixture**

Run: `swiftc DuoCam/Capability/*.swift scripts/make-fixture/main.swift -o .build/make-fixture && .build/make-fixture > DuoCam/Support/CapabilitiesFixture.json && grep -c '"lensID"' DuoCam/Support/CapabilitiesFixture.json`
Expected: `1116` (video 352 + 352 + 304 + 48 + 48, photo 6 + 3 + 1 + 1 + 1).

- [ ] **Step 5: Run to see it pass** — `scripts/test.sh CaptureCapabilitiesTests`. Expected: `** TEST SUCCEEDED **`.
- [ ] **Step 6: Commit** — `git add DuoCam.xcodeproj Config scripts DuoCam DuoCamTests && git commit -m "feat: add project, simulator test script and capability model with fixture"`

---

### Task 2: Record and photo selection resolvers

**Files:**
- Create in `DuoCam/Capability/`: `RecordSelection.swift`, `RecordRow.swift`, `Chip.swift`, `RecordSelectionResolver.swift`, `PhotoSelection.swift`, `PhotoRow.swift`, `PhotoSelectionResolver.swift`
- Test: `DuoCamTests/RecordSelectionResolverTests.swift`, `DuoCamTests/PhotoSelectionResolverTests.swift`

**Interfaces:**
- Consumes: Task 1 types.
- Produces:

```swift
struct RecordSelection: Codable, Sendable, Hashable { var family: CodecFamily; var quality: String; var resolution: Resolution; var frameRate: Int; var colour: ColourMode }
enum RecordRow: CaseIterable, Sendable { case codec, quality, resolution, frameRate, colour; var title: String; func columns(isWide: Bool) -> Int }  // as prototype
struct Chip: Identifiable, Equatable, Sendable { let id: String; let title: String; let detail: String?; let isAvailable: Bool; let reason: String? }
struct RecordSelectionResolver: Sendable {
    init(options: [VideoOption], lens: Lens?)                         // keeps options for lens?.id only
    func chips(_ row: RecordRow, for selection: RecordSelection) -> [Chip]
    func reasonLine(_ row: RecordRow, for selection: RecordSelection) -> String?          // first dimmed chip's reason
    func select(_ row: RecordRow, chipID: String, in selection: RecordSelection) -> RecordSelection?
    func settled(_ selection: RecordSelection) -> RecordSelection?   // nil only when the lens has no video options
    func option(for selection: RecordSelection) -> VideoOption?
    func defaultSelection() -> RecordSelection?                       // HEVC High 4K 30 Rec. 709 when present, else settled(first option)
}
struct PhotoSelection: Codable, Sendable, Hashable { var format: PhotoFormat; var megapixels: Int }
enum PhotoRow: CaseIterable, Sendable { case format, resolution; var title: String }  // "Format", "Resolution"
struct PhotoSelectionResolver: Sendable {
    init(options: [PhotoOption], lenses: [Lens], lensID: String)
    func chips(_ row: PhotoRow, for selection: PhotoSelection) -> [Chip]
    func select(_ row: PhotoRow, chipID: String, in selection: PhotoSelection) -> PhotoSelection?
    func settled(_ selection: PhotoSelection) -> PhotoSelection?; func option(for selection: PhotoSelection) -> PhotoOption?
    func defaultSelection() -> PhotoSelection?                        // RAW + HEIF at the largest size when present, else HEIF largest
}
```

Rules the signatures do not decide:
- Chip ids: codec `family.rawValue`, quality the label, resolution `Resolution.id`, rate `String(rate)`, colour `ColourMode.rawValue`. Titles are display strings; resolution chips carry `detail`.
- Video rows list only values present on the current lens; the quality row lists only the selected family's qualities. Order: `CodecFamily` case order; ProRes 4444 XQ, 4444, 422 HQ, 422, 422 LT, 422 Proxy; ProRes RAW, ProRes RAW HQ; Max, High, Medium, Low, Standard; resolutions by descending pixel count; rates ascending; `ColourMode` case order.
- A chip is available when at least one option matches every selection in the rows above it plus the chip.
- Reasons, N = `codec.displayName`, R = resolution label. Resolution: above the largest available "N records at up to R.", else "N is not available at R.". Frame rate: above max "N at R records at up to M fps.", below min "N at R records at M fps or more.", else "N at R does not record at F fps.". Colour: none with this family on the lens "C is not available with FAMILY.", none at this quality and resolution "C is not available with N at R.", else "C is not available at F fps.".
- Nearest valid, top to bottom after any change: same value if valid; frame rate the nearest lower available, else first available; resolution the largest available not above the old pixel count, else first available; other rows first available.
- The photo format row lists every `PhotoFormat` any lens has. One missing on this lens is dimmed with "RAW needs the A or B lens." (both RAW formats) or "HEIF needs the A lens.", naming lenses that have it in lens order, joined "A, B or C". Resolution chips are this lens's megapixel values; one not offered with the current format reads "FORMAT records at up to M MP.".

- [ ] **Step 1: Write the failing tests**

```swift
@Suite struct RecordSelectionResolverTests {
    let uhd = Resolution.named(width: 3840, height: 2160), fhd = Resolution.named(width: 1920, height: 1080)
    func resolver(_ id: String) throws -> RecordSelectionResolver {
        let caps = try Fixture.load(); return RecordSelectionResolver(options: caps.videoOptions, lens: caps.lenses.first { $0.id == id })
    }
    @Test func frameRatesAboveTheLimitAreDimmedWithAComputedReason() throws {
        let s = RecordSelection(family: .proRes, quality: "422 HQ", resolution: uhd, frameRate: 30, colour: .appleLog2)
        let chips = try resolver("wide").chips(.frameRate, for: s)
        #expect(chips.map(\.id) == ["24", "25", "30", "48", "50", "60", "100", "120"])
        #expect(chips.filter(\.isAvailable).map(\.id) == ["24", "25", "30"])
        #expect(try resolver("wide").reasonLine(.frameRate, for: s) == "ProRes 422 HQ at 4K records at up to 30 fps.")
    }
    @Test func colourReasonsComeFromTheData() throws {
        let h264 = RecordSelection(family: .h264, quality: "Max", resolution: fhd, frameRate: 30, colour: .rec709)
        #expect(try resolver("wide").chips(.colour, for: h264).first { $0.id == "HLG" }?.reason == "HLG is not available with H.264.")
        let hevc120 = RecordSelection(family: .hevc, quality: "Max", resolution: fhd, frameRate: 120, colour: .rec709)
        #expect(try resolver("wide").chips(.colour, for: hevc120).first { $0.id == "Apple Log 2" }?.reason == "Apple Log 2 is not available at 120 fps.")
    }
    @Test func rowsListOnlyThisLensAndFamily() throws {
        let s = RecordSelection(family: .hevc, quality: "High", resolution: uhd, frameRate: 30, colour: .rec709)
        #expect(try resolver("wide").chips(.quality, for: s).map(\.id) == ["Max", "High", "Medium", "Low"])
        #expect(try resolver("outer").chips(.codec, for: s).map(\.id) == ["hevc", "h264"])
    }
    @Test func changingFamilyMovesLowerRowsToNearestValid() throws {
        let s = RecordSelection(family: .hevc, quality: "Max", resolution: fhd, frameRate: 120, colour: .rec709)
        #expect(try resolver("wide").select(.codec, chipID: "proRes", in: s) == RecordSelection(family: .proRes, quality: "422 HQ", resolution: fhd, frameRate: 60, colour: .rec709))
    }
    @Test func lensWithoutSelectionMovesToNearestValid() throws {
        let s = RecordSelection(family: .proRes, quality: "422 HQ", resolution: uhd, frameRate: 30, colour: .appleLog2)
        #expect(try resolver("ultraWide").settled(s) == RecordSelection(family: .proRes, quality: "422 HQ", resolution: fhd, frameRate: 30, colour: .appleLog2))
        let outer = try resolver("outer"), front = outer.settled(s)
        #expect(front == RecordSelection(family: .hevc, quality: "Max", resolution: fhd, frameRate: 30, colour: .rec709))
        #expect(front.flatMap { outer.option(for: $0) } != nil)
    }
    @Test func lensWithNoOptionsReturnsNil() throws {
        let s = RecordSelection(family: .hevc, quality: "Max", resolution: fhd, frameRate: 30, colour: .rec709)
        #expect(RecordSelectionResolver(options: try Fixture.load().videoOptions, lens: nil).settled(s) == nil)
    }
    @Test func defaultIsHEVCHigh4K30() throws {
        #expect(try resolver("wide").defaultSelection() == RecordSelection(family: .hevc, quality: "High", resolution: uhd, frameRate: 30, colour: .rec709))
    }
}

@Suite struct PhotoSelectionResolverTests {
    func resolver(_ id: String) throws -> PhotoSelectionResolver {
        let caps = try Fixture.load(); return PhotoSelectionResolver(options: caps.photoOptions, lenses: caps.lenses, lensID: id)
    }
    @Test func rawIsDimmedOnTheTwoTimesLensWithLensNames() throws {
        let chips = try resolver("wide@2").chips(.format, for: PhotoSelection(format: .heif, megapixels: 12))
        #expect(chips.map(\.id) == ["RAW", "RAW + HEIF", "HEIF"])
        #expect(chips[0].reason == "RAW needs the 0.5x or 1x lens."); #expect(chips[1].reason == "RAW needs the 0.5x or 1x lens.")
        #expect(chips[2].isAvailable)
    }
    @Test func lensSwitchAndDefault() throws {
        #expect(try resolver("wide@2").settled(PhotoSelection(format: .raw, megapixels: 48)) == PhotoSelection(format: .heif, megapixels: 12))
        #expect(try resolver("wide").defaultSelection() == PhotoSelection(format: .rawPlusHEIF, megapixels: 48))
    }
}
```

- [ ] **Step 2: Run to see them fail** — `scripts/test.sh RecordSelectionResolverTests`. Expected: `cannot find 'RecordSelectionResolver'`.
- [ ] **Step 3: Implement the types to the rules above.**
- [ ] **Step 4: Run to see them pass** — `scripts/test.sh RecordSelectionResolverTests && scripts/test.sh PhotoSelectionResolverTests`. Expected: `** TEST SUCCEEDED **` twice.
- [ ] **Step 5: Commit** — `git add DuoCam/Capability DuoCamTests && git commit -m "feat: add record and photo selection resolvers with computed reasons"`

---

### Task 3: Data rate and remaining time

**Files:** Create `DuoCam/Capability/DataRateEstimator.swift`; Test `DuoCamTests/DataRateEstimatorTests.swift`

**Interfaces:**
- Consumes: `VideoOption`, `BitrateTier.bitsPerPixelPerFrame`.
- Produces:

```swift
enum DataRateEstimator {
    static let reserveBytes: Int64 = 2_000_000_000; static let lowStorageMinutes = 5
    static func megabitsPerSecond(for option: VideoOption) -> Double
    static func gigabytesPerMinute(for option: VideoOption) -> Double           // Mbit/s * 60 / 8 / 1000
    static func minutesRemaining(freeBytes: Int64, option: VideoOption) -> Int  // floor((free - reserve) / bytes per minute), never below 0
    static func isLowStorage(minutes: Int) -> Bool                              // minutes < lowStorageMinutes
    static func footer(for option: VideoOption, freeBytes: Int64) -> String    // "About 6.6 GB per minute. 21 min left."
}
```

Figures: ProRes Mbit/s at 1920 x 1080, 29.97 fps: Proxy 45, LT 102, 422 147, 422 HQ 220, 4444 330, 4444 XQ 500, scaled by `pixelCount / 2_073_600` and `frameRate / 29.97`. ProRes RAW and RAW HQ use the 4444 XQ figure (no figure was given; this overstates, so remaining time is never too long, and the sidecar measures the real rate). HEVC: `bitsPerPixelPerFrame * pixelCount * frameRate / 1e6`. H.264: the HEVC figure times 1.6. Quality "Standard" uses the High tier.

- [ ] **Step 1: Write the failing tests**

```swift
@Suite struct DataRateEstimatorTests {
    func opt(_ f: CodecFamily, _ q: String, _ t: BitrateTier?, _ w: Int, _ h: Int, _ fps: Int) -> VideoOption {
        VideoOption(lensID: "wide", codec: VideoCodec(family: f, quality: q, codecType: "x", bitrateTier: t), resolution: .named(width: w, height: h), frameRate: fps, colour: .rec709)
    }
    func mbps(_ o: VideoOption) -> Double { DataRateEstimator.megabitsPerSecond(for: o) }
    @Test func proResScalesByPixelsAndFrameRate() {
        #expect(abs(mbps(opt(.proRes, "422 HQ", nil, 1920, 1080, 30)) - 220.2202) < 0.001)
        #expect(abs(mbps(opt(.proRes, "422 HQ", nil, 3840, 2160, 30)) - 880.8809) < 0.001)
        #expect(abs(mbps(opt(.proRes, "422 Proxy", nil, 1920, 1080, 24)) - 36.0360) < 0.001)
    }
    @Test func hevcAndH264UseBitsPerPixel() {
        #expect(abs(mbps(opt(.hevc, "Max", .max, 3840, 2160, 30)) - 44.78976) < 0.0001)
        #expect(abs(mbps(opt(.hevc, "Low", .low, 1920, 1080, 120)) - 9.95328) < 0.0001)
        #expect(abs(mbps(opt(.h264, "High", .high, 3840, 2160, 30)) - 43.794432) < 0.0001)
    }
    @Test func remainingTimeKeepsTheReserve() {
        let hq = opt(.proRes, "422 HQ", nil, 3840, 2160, 30)
        #expect(abs(DataRateEstimator.gigabytesPerMinute(for: hq) - 6.6066) < 0.001)
        #expect(DataRateEstimator.minutesRemaining(freeBytes: 141_000_000_000, option: hq) == 21)
        #expect(DataRateEstimator.minutesRemaining(freeBytes: 1_500_000_000, option: hq) == 0)
        #expect(DataRateEstimator.footer(for: hq, freeBytes: 141_000_000_000) == "About 6.6 GB per minute. 21 min left.")
        #expect(DataRateEstimator.isLowStorage(minutes: 4)); #expect(!DataRateEstimator.isLowStorage(minutes: 5))
    }
}
```

- [ ] **Step 2: Run to see them fail** — `scripts/test.sh DataRateEstimatorTests`. Expected: `cannot find 'DataRateEstimator'`.
- [ ] **Step 3: Implement `DataRateEstimator`.**
- [ ] **Step 4: Run to see them pass.**
- [ ] **Step 5: Commit** — `git add DuoCam/Capability DuoCamTests && git commit -m "feat: add data rate and remaining time estimates"`

---

### Task 4: Record settings UI

**Files:**
- Create in `DuoCam/UI/`: `Theme.swift` (prototype copy), `ChipRow.swift`, `ChipButton.swift` (split from the prototype's `ChipRow.swift`), `RecordSettingsSheet.swift`, `VideoRecordRows.swift`, `PhotoRows.swift`
- Create in `DuoCam/App/`: `CaptureMode.swift` (`nonisolated enum CaptureMode: String, Codable, Sendable { case video, photo }`), `LaunchConfig.swift`, `LaunchOrientation.swift`, `LaunchScreen.swift`, `SimulatedState.swift`
- Create: `scripts/shot.sh`. Modify: `DuoCam/App/DuoCamApp.swift`
- Test: `DuoCamTests/LaunchConfigTests.swift`

**Interfaces:**
- Consumes: Tasks 1 to 3.
- Produces:

```swift
struct LaunchConfig: Equatable, Sendable { var orientation: LaunchOrientation?; var mode: CaptureMode = .video; var screen: LaunchScreen = .main
    var isRecording = false; var simulatedState: SimulatedState?; var freeSpaceMarginMB: Int?; var keepsSweepClips = false
    var isScripted = false   // true when -orientation, -mode, -screen, -recording or -state parsed to a valid value; such launches never restore or save selections
    static func parse(_ args: [String]) -> LaunchConfig }
enum LaunchOrientation: String { case landscape, portrait }
enum LaunchScreen: String { case main, record, sweep }
enum SimulatedState: String { case scanning, cameraDenied, micDenied, lowStorage, storageFull, pressure }   // honoured only in the Simulator
struct RecordSettingsSheet: View { let mode: CaptureMode; let capabilities: CaptureCapabilities; let lens: Lens?
    @Binding var record: RecordSelection; @Binding var photo: PhotoSelection; let freeBytes: Int64 }
struct ChipRow: View { let title: String; let chips: [Chip]; let selectedID: String; let reason: String?; let columns: Int; let onSelect: (String) -> Void }
```

Flags: `-orientation landscape|portrait`, `-mode video|photo`, `-screen main|record|sweep`, `-recording on|off`, `-state <SimulatedState>`, `-freeSpaceMarginMB <Int>`, `-keepSweepClips on`; unknown values fall back to defaults. The sheet renders the five `RecordRow`s in video mode (chips from `chips`, caption from `reasonLine`, a tap calls `select` and writes the binding) with `DataRateEstimator.footer` below, or the two `PhotoRow`s in photo mode; titles "Record settings" / "Photo settings"; close is `Button(role: .close)`; chips keep the prototype styling (selected `.glassProminent` tinted `Theme.accent`, others `.glass`, unavailable at 0.35 opacity and disabled). For this task `DuoCamApp` loads the fixture, holds `@State` selections from `defaultSelection()` on lens `wide` with `freeBytes` 141_000_000_000, presents the sheet over black when `-screen record`, and applies `-orientation` with `requestGeometryUpdate` as the prototype app does.

`scripts/shot.sh <name> [launch args...]`:

```bash
#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
NAME="$1"; shift
UDID="$(scripts/sim-udid.sh)"
xcodebuild build -quiet -project DuoCam.xcodeproj -scheme DuoCam -destination "id=$UDID" -derivedDataPath .build CODE_SIGNING_ALLOWED=NO
xcrun simctl install "$UDID" .build/Build/Products/Debug-iphonesimulator/DuoCam.app
xcrun simctl launch --terminate-running-process "$UDID" local.duocam.app "$@" >/dev/null
sleep 4
mkdir -p docs/screenshots/p1a
xcrun simctl io "$UDID" screenshot --display=1 "docs/screenshots/p1a/$NAME.png"
```

- [ ] **Step 1: Write the failing test**

```swift
@Suite struct LaunchConfigTests {
    @Test func parsesEveryFlag() {
        let c = LaunchConfig.parse(["app", "-orientation", "landscape", "-mode", "photo", "-screen", "record", "-recording", "on",
                                    "-state", "micDenied", "-freeSpaceMarginMB", "300", "-keepSweepClips", "on"])
        #expect(c == LaunchConfig(orientation: .landscape, mode: .photo, screen: .record, isRecording: true, simulatedState: .micDenied, freeSpaceMarginMB: 300, keepsSweepClips: true, isScripted: true))
        #expect(!LaunchConfig.parse(["app", "-freeSpaceMarginMB", "300"]).isScripted)
    }
    @Test func unknownValuesFallBack() { #expect(LaunchConfig.parse(["app", "-mode", "cinema", "-screen", "monitor"]) == LaunchConfig()) }
}
```

- [ ] **Step 2: Run to see it fail** — `scripts/test.sh LaunchConfigTests`.
- [ ] **Step 3: Implement the files, porting the prototype views onto the resolvers.**
- [ ] **Step 4: Run to see it pass.**
- [ ] **Step 5: Screenshot and look** (Read each PNG)

```bash
scripts/shot.sh t4-record-video-h -orientation landscape -mode video -screen record
scripts/shot.sh t4-record-video-v -orientation portrait -mode video -screen record
scripts/shot.sh t4-record-photo-v -orientation portrait -mode photo -screen record
```

Pass when the video shots show Codec ProRes, HEVC, H.264 (no RAW: the fixture has none) with HEVC selected; Quality Max/High/Medium/Low; Resolution 4K and 1080p with sizes; Frame rate 24 to 120 with 100 and 120 dimmed and "HEVC High at 4K records at up to 60 fps."; Colour with Apple Log dimmed and "Apple Log is not available with HEVC."; footer "About 0.2 GB per minute. 677 min left."; nothing clipped; the close button in the strip. The photo shot shows RAW, RAW + HEIF, HEIF with RAW + HEIF and 48 MP selected.

- [ ] **Step 6: Commit** — `git add DuoCam scripts DuoCamTests docs/screenshots/p1a && git commit -m "feat: add record settings panel driven by the capability model"`

---

### Task 5: CameraModel and folded layouts with the strip

**Files:**
- Create in `DuoCam/App/`: `CameraModel.swift`, `CameraSheet.swift`, `CameraPhase.swift`
- Create in `DuoCam/UI/`: `CameraRootView.swift`, `FoldedHorizontalView.swift`, `FoldedVerticalView.swift`, `FoldedVerticalVideoView.swift`, `StripToolbar.swift`, `TopReadoutBar.swift`, `ReadoutView.swift`, `TimecodeReadout.swift`, `BottomBar.swift`, `FormatButton.swift`, `CaptureButton.swift`, `AudioMetersView.swift`, `ViewfinderStandIn.swift`, `ViewfinderArea.swift`
- Create: `DuoCam/Support/SavedSelections.swift`
- Modify: `DuoCam/App/DuoCamApp.swift` (root becomes `CameraRootView`)
- Test: `DuoCamTests/CameraModelTests.swift`, `DuoCamTests/SavedSelectionsTests.swift`

**Interfaces:**
- Consumes: Tasks 1 to 4.
- Produces:

```swift
enum CameraSheet: String, Identifiable { case record, sweep; var id: String { rawValue } }
enum CameraPhase: Equatable, Sendable { case scanning, ready, simulator, cameraDenied, cameraRestricted, failed(String) }
nonisolated struct SavedSelections: Codable, Sendable, Equatable {   // UserDefaults key "savedSelections", JSON
    var mode: CaptureMode; var lensID: String; var record: RecordSelection; var photo: PhotoSelection
    static func load(from defaults: UserDefaults) -> SavedSelections?    // nil when missing or undecodable
    func save(to defaults: UserDefaults) }
@Observable final class CameraModel {
    init(config: LaunchConfig, capabilities: CaptureCapabilities, isSimulator: Bool, defaults: UserDefaults = .standard)
    var mode: CaptureMode; var record: RecordSelection; var photo: PhotoSelection; var sheet: CameraSheet?
    var phase: CameraPhase; var freeBytes: Int64; var notice: String?; var meterLevels: [Double]; var lastCapture: URL?
    private(set) var capabilities: CaptureCapabilities; private(set) var lensID: String
    private(set) var isRecording: Bool; private(set) var recordingStart: Date?
    var lenses: [Lens] { get }; var currentLens: Lens? { get }
    var recordResolver: RecordSelectionResolver { get }; var photoResolver: PhotoSelectionResolver { get }
    var currentVideoOption: VideoOption? { get }; var currentPhotoOption: PhotoOption? { get }
    var summaryParts: [String] { get }   // video [family title, resolution label, colour shortName]; photo [format, "48 MP"]
    var remainingText: String { get }    // "21 min"
    var canCapture: Bool { get }         // phase == .ready
    func selectLens(_ id: String)        // settles record and photo; an unknown id is ignored
    func replaceCapabilities(_ capabilities: CaptureCapabilities)   // keeps the lens if present, else the first; settles both
    func capturePressed()                // filled by Tasks 8 and 9
}
```

Port the prototype layout: `CameraRootView` shows `FoldedHorizontalView` when `verticalSizeClass == .compact`, else `FoldedVerticalVideoView` or `FoldedVerticalView` by mode, in a `NavigationStack` with `.toolbar { StripToolbar(model:isLandscape:) }`, `.persistentSystemOverlays(.hidden)`, black background, and the record sheet. `ViewfinderArea` shows `ViewfinderStandIn` (prototype view minus `isFlat`) in phase `.simulator`. `StripToolbar` items, vertical order (reversed when horizontal, as the prototype): Mode (Menu Photo/Video), Lens (Menu over `lenses`, label `currentLens.label`), Record settings (`slider.horizontal.3`), Library (Task 11; here a disabled `photo.on.rectangle` labelled "Library"). `TopReadoutBar` shows FPS (selection), SHUTTER, TIMECODE, ISO, WB, TINT as `ReadoutView`s (caption over monospaced value, not a button), live values `--` until Task 10. Default lens `wide` when present, else the first. Restore: unless `config.isScripted`, `init` reads `SavedSelections.load(from: defaults)`; a saved lens id that no longer exists falls back to the default lens; saved selections are never trusted as is but passed through `recordResolver.settled` and `photoResolver.settled` (falling back to `defaultSelection()` on nil). Unless scripted, every change to mode, lens, record or photo saves a new `SavedSelections`. The capture button is disabled when `!canCapture`; `-recording on` starts the model in the recording state for screenshots.

- [ ] **Step 1: Write the failing tests**

```swift
@MainActor @Suite struct CameraModelTests {
    @Test func selectingALensSettlesTheRecordSelection() throws {
        let model = CameraModel(config: LaunchConfig(), capabilities: try Fixture.load(), isSimulator: true, defaults: try Fixture.freshDefaults())
        model.record = RecordSelection(family: .proRes, quality: "422 HQ", resolution: .named(width: 3840, height: 2160), frameRate: 30, colour: .appleLog2)
        model.selectLens("ultraWide")
        #expect(model.record.resolution.label == "1080p"); #expect(model.summaryParts == ["ProRes", "1080p", "Log 2"])
        model.selectLens("nope"); #expect(model.lensID == "ultraWide")
    }
    @Test func simulatorPhaseAndLaunchState() throws {
        let model = CameraModel(config: .parse(["app", "-mode", "photo", "-recording", "on"]), capabilities: try Fixture.load(), isSimulator: true, defaults: try Fixture.freshDefaults())
        #expect(model.phase == .simulator); #expect(!model.canCapture)
        #expect(model.summaryParts == ["RAW + HEIF", "48 MP"]); #expect(model.isRecording && model.recordingStart != nil)
    }
}

@MainActor @Suite struct SavedSelectionsTests {
    let uhd = Resolution.named(width: 3840, height: 2160)
    @Test func selectionsRoundTripThroughARelaunch() throws {
        let defaults = try Fixture.freshDefaults(), caps = try Fixture.load()
        let first = CameraModel(config: LaunchConfig(), capabilities: caps, isSimulator: true, defaults: defaults)
        first.mode = .photo; first.selectLens("ultraWide")
        first.record = RecordSelection(family: .h264, quality: "Low", resolution: .named(width: 1920, height: 1080), frameRate: 25, colour: .rec709)
        let second = CameraModel(config: LaunchConfig(), capabilities: caps, isSimulator: true, defaults: defaults)
        #expect(second.mode == .photo); #expect(second.lensID == "ultraWide"); #expect(second.record == first.record)
        #expect(SavedSelections.load(from: defaults)?.record == first.record)
    }
    @Test func staleSelectionMovesToNearestValid() throws {
        let defaults = try Fixture.freshDefaults()
        SavedSelections(mode: .video, lensID: "wide", record: RecordSelection(family: .raw, quality: "ProRes RAW", resolution: uhd, frameRate: 30, colour: .rec709),
                        photo: PhotoSelection(format: .raw, megapixels: 48)).save(to: defaults)
        let model = CameraModel(config: LaunchConfig(), capabilities: try Fixture.load(), isSimulator: true, defaults: defaults)
        #expect(model.record == RecordSelection(family: .proRes, quality: "422 HQ", resolution: uhd, frameRate: 30, colour: .rec709))
    }
    @Test func scriptedLaunchNeitherRestoresNorSaves() throws {
        let defaults = try Fixture.freshDefaults()
        let saved = SavedSelections(mode: .video, lensID: "outer", record: RecordSelection(family: .h264, quality: "Low", resolution: .named(width: 1920, height: 1080), frameRate: 25, colour: .rec709), photo: PhotoSelection(format: .heif, megapixels: 12))
        saved.save(to: defaults)
        let model = CameraModel(config: .parse(["app", "-mode", "photo"]), capabilities: try Fixture.load(), isSimulator: true, defaults: defaults)
        #expect(model.lensID == "wide"); model.selectLens("ultraWide")
        #expect(SavedSelections.load(from: defaults) == saved)
    }
}
```

- [ ] **Step 2: Run to see them fail** — `scripts/test.sh CameraModelTests && scripts/test.sh SavedSelectionsTests`.
- [ ] **Step 3: Implement the model and port the views.**
- [ ] **Step 4: Run to see them pass.**
- [ ] **Step 5: Screenshot and look**

```bash
scripts/shot.sh t5-video-h -orientation landscape -mode video
scripts/shot.sh t5-video-v -orientation portrait -mode video
scripts/shot.sh t5-photo-v -orientation portrait -mode photo
scripts/shot.sh t5-photo-h -orientation landscape -mode photo
scripts/shot.sh t5-recording-h -orientation landscape -mode video -recording on
```

Pass when: horizontal shots have the strip on the left with four glass items grouped at its bottom; readouts in the top letterbox bar; the bottom bar holds "HEVC  4K  Rec. 709", meters, remaining time and record button, none over the picture; vertical shots have the strip on the right; the stand-in reads "No camera in Simulator"; `t5-recording-h` shows a running timecode and the stop symbol. Compare spacing with `prototype/screenshots/h-video.png` and `v-photo.png`.

- [ ] **Step 6: Commit** — `git add DuoCam DuoCamTests docs/screenshots/p1a && git commit -m "feat: add camera model and folded layouts with the strip toolbar"`

---

### Task 6: CameraSession, preview and interruptions

**Files:**
- Create in `DuoCam/Capability/`: `StandardFrameRates.swift`, `LensLabel.swift`
- Create in `DuoCam/Capture/`: `CameraSession.swift`, `CameraSessionError.swift`, `PreviewSource.swift`, `SessionConfiguration.swift`, `SessionEvent.swift`, `InterruptionReason.swift`, `PressureLevel.swift`, `CaptureAccess.swift`, `AccessState.swift`, `LensDiscovery.swift`, `DeviceIdentity.swift`
- Create in `DuoCam/UI/`: `CameraPreviewView.swift`, `PreviewUIView.swift`
- Modify: `DuoCam/App/CameraModel.swift`, `DuoCam/App/DuoCamApp.swift`, `DuoCam/UI/ViewfinderArea.swift`
- Test: `DuoCamTests/CaptureHelpersTests.swift`

**Interfaces:**
- Consumes: Task 5 `CameraModel`; Task 1 `Lens`, `VideoOption`, `PhotoOption`, `ColourMode(captureColorSpace:)`.
- Produces:

```swift
enum StandardFrameRates { static let all = [24, 25, 30, 48, 50, 60, 100, 120]
    static func collapse(_ ranges: [ClosedRange<Double>]) -> [Int] }   // r kept when some range has lower - 0.01 <= r <= upper + 0.01
enum LensLabel { static func text(kind: LensKind, zoomFactor: Double, localizedName: String) -> String }
enum AccessState: Sendable, Equatable { case notDetermined, authorized, denied, restricted }
struct CaptureAccess: Sendable, Equatable { var camera: AccessState; var microphone: AccessState; var canUseCamera: Bool { get }; var recordsSound: Bool { get } }
enum InterruptionReason: Sendable, Equatable { case background, cameraInUse, multipleForegroundApps, systemPressure, microphoneInUse, other
    init(avReason rawValue: Int); var notice: String? { get } }
enum PressureLevel: String, Sendable { case nominal, fair, serious, critical, shutdown }
enum SessionEvent: Sendable, Equatable { case interrupted(InterruptionReason), interruptionEnded, runtimeError(String), pressure(PressureLevel, isThermal: Bool) }
struct SessionConfiguration: Sendable, Equatable { var lens: Lens; var mode: CaptureMode; var video: VideoOption?; var photo: PhotoOption?; var includesAudio: Bool }
struct PreviewSource: @unchecked Sendable { let session: AVCaptureSession }
enum LensDiscovery { static func lenses() -> [Lens] }      // adds "<wide uniqueID>@2" at zoom 2
enum DeviceIdentity { static func osBuild() -> String; static func modelIdentifier() -> String }   // sysctl kern.osversion; utsname machine as probe Inventory.device()
enum CameraSessionError: Error, CustomStringConvertible { case deviceMissing(lensID: String), cannotAddInput(lensID: String), cannotAddOutput(name: String), noMatchingFormat(option: String), lockFailed(reason: String) }
actor CameraSession {
    nonisolated let previewSource: PreviewSource; nonisolated let events: AsyncStream<SessionEvent>
    init()                                                  // executor: DispatchSerialQueue "duocam.session" via unownedExecutor
    static func requestAccess() async -> CaptureAccess
    func configure(_ configuration: SessionConfiguration) throws(CameraSessionError)
    func start(); func stop()
}
extension CameraModel { func start(session: CameraSession) async }
```

Decisions the signatures leave open:
- Lens labels: wide at zoom 1 "1x", at zoom 2 "2x", ultraWide "0.5x", outer and inner ultra wide use `localizedName` (the SDK does not say which is the outer front camera). Discovery covers `.builtInWideAngleCamera`, `.builtInUltraWideCamera`, `.builtInOuterUltraWideCamera`, `.builtInInnerUltraWideCamera`.
- `configure`, inside `lockForConfiguration`: `automaticallyConfiguresCaptureDeviceForWideColor = false`; `activeFormat` = a format with the option's dimensions, colour space and a range containing the frame rate, preferring non-binned; then `activeColorSpace`; then min and max frame duration `1/frameRate`; then `videoZoomFactor = lens.zoomFactor`. `video == nil` keeps the device default (until Task 7). Photo mode never selects Apple Log or Apple Log 2 (photo capture is unsupported there, capture sheet section 3); it takes P3 when offered, else Rec. 709.
- Events: `AVCaptureSession.wasInterruptedNotification` (`AVCaptureSessionInterruptionReasonKey`), `interruptionEndedNotification`, `runtimeErrorNotification`, KVO on `systemPressureState` (thermal when factors contain `.systemTemperature` or `.cameraTemperature`).
- Notices: cameraInUse "Camera paused. Another app is using it."; multipleForegroundApps "Camera paused while another app is on screen."; systemPressure "Camera paused to protect the phone."; microphoneInUse "Microphone in use by another app."; other "Camera paused."; background `nil`.
- `PreviewUIView` uses `AVCaptureVideoPreviewLayer` as `layerClass`, `.resizeAspect`, and on the main actor builds `AVCaptureDevice.RotationCoordinator(device:previewLayer:)` from the layer's input device (`as?`, never `as!`), applying `videoRotationAngleForHorizonLevelPreview`.
- `CameraModel.start(session:)`: request access (phase `.cameraDenied` / `.cameraRestricted` on refusal), discover lenses, configure the current lens with `video: nil`, start, fold `events` into `notice` and `phase`. `DuoCamApp` calls it from `.task` outside the Simulator; `ViewfinderArea` shows `CameraPreviewView` in `.ready`.

- [ ] **Step 1: Write the failing tests**

```swift
@Suite struct CaptureHelpersTests {
    @Test func frameRatesCollapseToTheStandardList() {
        #expect(StandardFrameRates.collapse([1...30]) == [24, 25, 30]); #expect(StandardFrameRates.collapse([1...60]) == [24, 25, 30, 48, 50, 60])
        #expect(StandardFrameRates.collapse([1...30, 120...120]) == [24, 25, 30, 120]); #expect(StandardFrameRates.collapse([23.976...29.97]) == [24, 25, 30])
        #expect(StandardFrameRates.collapse([]) == [])
    }
    @Test func coloursAndLensLabels() {
        #expect([0, 1, 2, 3, 4].compactMap(ColourMode.init(captureColorSpace:)) == [.rec709, .p3, .hlg, .appleLog, .appleLog2])
        #expect(LensLabel.text(kind: .wide, zoomFactor: 2, localizedName: "Back Camera") == "2x")
        #expect(LensLabel.text(kind: .ultraWide, zoomFactor: 1, localizedName: "Back Ultra Wide Camera") == "0.5x")
        #expect(LensLabel.text(kind: .outerUltraWide, zoomFactor: 1, localizedName: "Front Camera") == "Front Camera")
    }
    @Test func interruptionNotices() {
        #expect(InterruptionReason(avReason: 3) == .cameraInUse); #expect(InterruptionReason.cameraInUse.notice == "Camera paused. Another app is using it.")
        #expect(InterruptionReason(avReason: 1).notice == nil); #expect(InterruptionReason(avReason: 99) == .other)
    }
}
```

- [ ] **Step 2: Run to see them fail** — `scripts/test.sh CaptureHelpersTests`.
- [ ] **Step 3: Implement the files to the decisions above.**
- [ ] **Step 4: Run all tests, then `scripts/shot.sh t6-video-h -orientation landscape`** — Expected: `** TEST SUCCEEDED **`; the shot matches `t5-video-h`.
- [ ] **Step 5: Commit** — `git add DuoCam DuoCamTests docs/screenshots/p1a && git commit -m "feat: add camera session, preview and interruption events"`

**On the device** (owner runs from Xcode on the Duo):
- [ ] First launch asks for camera, then microphone. With both allowed the live picture shows upright and aspect-fit in all four orientations, nothing over it.
- [ ] The lens menu lists 0.5x, 1x, 2x and two front lenses by `localizedName`. Write down which name is the outer front camera; a later plan needs it.
- [ ] Background and return: the preview resumes. Fold and unfold: note any notice and whether the preview resumes.
- [ ] Top of the horizontal strip: is the camera hole or clock there, and does any strip item sit under it?

---

### Task 7: Capability scan with cache

**Files:**
- Create in `DuoCam/Capability/`: `FormatDescriptor.swift`, `PhotoSize.swift`, `CapabilityMapper.swift`, `CapabilityCache.swift`
- Create: `DuoCam/Capture/CapabilityScanner.swift`
- Modify: `DuoCam/App/CameraModel.swift`, `DuoCam/UI/ViewfinderArea.swift`
- Test: `DuoCamTests/CapabilityMapperTests.swift`, `DuoCamTests/CapabilityCacheTests.swift`

**Interfaces:**
- Consumes: Task 6 `LensDiscovery`, `DeviceIdentity`, `StandardFrameRates`, `CameraModel.start`; Task 5 `replaceCapabilities`.
- Produces:

```swift
struct PhotoSize: Sendable, Hashable { let width: Int; let height: Int }
struct FormatDescriptor: Sendable, Equatable { let lensID: String; let width: Int; let height: Int; let isBinned: Bool
    let frameRateRanges: [ClosedRange<Double>]
    let codecTypesByColourSpace: [Int: [String]]   // captureColorSpace raw value -> movie output availableVideoCodecTypes
    let allowsCompressionProperties: Bool          // supportedOutputSettingsKeys(for:) contains AVVideoCompressionPropertiesKey
    let maxPhotoDimensions: [PhotoSize]; let hasBayerRAW: Bool }
enum CapabilityMapper {
    static func codecs(fourCCs: [String], allowsCompressionProperties: Bool) -> [VideoCodec]
    static func videoOptions(from formats: [FormatDescriptor]) -> [VideoOption]          // deduplicated, row order
    static func photoOptions(from formats: [FormatDescriptor], lenses: [Lens]) -> [PhotoOption]
    static func capabilities(lenses: [Lens], formats: [FormatDescriptor], osBuild: String, modelIdentifier: String) -> CaptureCapabilities
}
struct CapabilityCache: Sendable { init(directory: URL)                               // file "capabilities.json"
    func load(osBuild: String, modelIdentifier: String) -> CaptureCapabilities?        // nil when missing, unreadable or the key differs
    func save(_ capabilities: CaptureCapabilities) throws(CapabilityError) }
enum CapabilityScanner { static func scan(lenses: [Lens]) async throws(CameraSessionError) -> [FormatDescriptor] }
extension CameraModel { func loadCapabilities(lenses: [Lens]) async }   // cache hit, else scan and save; phase .scanning meanwhile
```

Mapping: `aprn` RAW "ProRes RAW", `aprh` RAW "ProRes RAW HQ", `ap4x` "4444 XQ", `ap4h` "4444", `apch` "422 HQ", `apcn` "422", `apcs` "422 LT", `apco` "422 Proxy"; `hvc1` and `avc1` give the four tiers when `allowsCompressionProperties`, else one quality "Standard"; all other FourCCs (`jpeg`, `jxlc`, `muxa`, unknown) are dropped. Rates via `StandardFrameRates.collapse`. A zoom-2 lens reuses its device's descriptors. Photo: one option per format per size; RAW formats only when `hasBayerRAW` and zoom factor 1.

The scanner is a thin adapter modelled on `probe/DuoCamProbe/Inventory.swift` `scanOutputs`: a throwaway session per device with photo and movie outputs; one format per class (dimensions, colour-space set, frame-rate set); per class set `activeFormat`, then each supported `activeColorSpace` (wide-colour automation off), reading `availableVideoCodecTypes` each time; restore the original format. Reading codecs per colour space goes one step past "set the active format and read the codecs", because the codec list may depend on the colour space. The cache lives in `Application Support/DuoCam/`; after a scan a copy goes to `Documents/capabilities.json` for comparison with the probe report. While scanning, `ViewfinderArea` reads `Reading camera formats…`. The Simulator uses the fixture and never scans; there `-state scanning` sets phase `.scanning`.

- [ ] **Step 1: Write the failing tests**

```swift
@Suite struct CapabilityMapperTests {
    let wide = Lens(id: "W", kind: .wide, deviceUniqueID: "W", zoomFactor: 1, label: "1x"), tele = Lens(id: "W@2", kind: .wide, deviceUniqueID: "W", zoomFactor: 2, label: "2x")
    func fmt(_ w: Int, _ h: Int, _ ranges: [ClosedRange<Double>], _ codecs: [Int: [String]]) -> FormatDescriptor {
        FormatDescriptor(lensID: "W", width: w, height: h, isBinned: false, frameRateRanges: ranges, codecTypesByColourSpace: codecs,
                         allowsCompressionProperties: true, maxPhotoDimensions: [PhotoSize(width: 8064, height: 6048)], hasBayerRAW: true)
    }
    @Test func codecsMapAndUnknownsDrop() {
        #expect(CapabilityMapper.codecs(fourCCs: ["apch", "jpeg", "hvc1"], allowsCompressionProperties: false).map(\.quality) == ["422 HQ", "Standard"])
        #expect(CapabilityMapper.codecs(fourCCs: ["hvc1"], allowsCompressionProperties: true).map(\.quality) == ["Max", "High", "Medium", "Low"])
    }
    @Test func everyCombinationIsListedOnce() {
        let f = fmt(3840, 2160, [1...30], [0: ["apch"], 3: ["apch"]])
        let options = CapabilityMapper.videoOptions(from: [f, f])
        #expect(options.count == 6); #expect(Set(options.map(\.colour)) == [.rec709, .appleLog])
    }
    @Test func twoTimesLensCopiesVideoButNotRaw() {
        let caps = CapabilityMapper.capabilities(lenses: [wide, tele], formats: [fmt(1920, 1080, [1...60], [0: ["hvc1"]])], osBuild: "B", modelIdentifier: "M")
        #expect(caps.videoOptions(forLens: "W@2").count == caps.videoOptions(forLens: "W").count)
        #expect(caps.photoOptions(forLens: "W@2").map(\.format) == [.heif])
        #expect(Set(caps.photoOptions(forLens: "W").map(\.format)) == [.raw, .rawPlusHEIF, .heif])
    }
}

@Suite struct CapabilityCacheTests {
    func tempDirectory() -> URL { FileManager.default.temporaryDirectory.appending(path: UUID().uuidString) }
    @Test func olderOSBuildTriggersRescan() throws {
        let cache = CapabilityCache(directory: tempDirectory())
        var caps = try Fixture.load(); caps.osBuild = "24B91"; caps.modelIdentifier = "iPhone19,4"
        try cache.save(caps)
        #expect(cache.load(osBuild: "24B114", modelIdentifier: "iPhone19,4") == nil)
        #expect(cache.load(osBuild: "24B91", modelIdentifier: "iPhone19,5") == nil)
        #expect(cache.load(osBuild: "24B91", modelIdentifier: "iPhone19,4") == caps)
    }
    @Test func corruptFileIsAMiss() throws {
        let dir = tempDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: dir.appending(path: "capabilities.json"))
        #expect(CapabilityCache(directory: dir).load(osBuild: "B", modelIdentifier: "M") == nil)
    }
}
```

- [ ] **Step 2: Run to see them fail** — `scripts/test.sh CapabilityMapperTests`.
- [ ] **Step 3: Implement mapper, cache, scanner and `loadCapabilities`; `start(session:)` now loads capabilities before `configure` and passes `currentVideoOption` / `currentPhotoOption`.**
- [ ] **Step 4: Run all tests, then `scripts/shot.sh t7-scanning -orientation landscape -state scanning`** — Expected: pass; the viewfinder area shows only "Reading camera formats…".
- [ ] **Step 5: Commit** — `git add DuoCam DuoCamTests docs/screenshots/p1a && git commit -m "feat: scan camera formats once per OS build and cache the capabilities"`

**On the device:**
- [ ] First launch shows "Reading camera formats…", then the picture; note the scan time. The second launch skips it.
- [ ] Copy `capabilities.json` (Files > On My iPhone > DuoCam) and the probe's `duocam-probe-report.json` to the Mac and compare:

```bash
jq '[.cameras[] | {deviceType, codecs: ([.formats[].movieCodecTypes[]] | unique), colours: ([.formats[].colorSpaces[]] | unique)}]' duocam-probe-report.json
jq '[.videoOptions | group_by(.lensID)[] | {lens: .[0].lensID, codecs: (map(.codec.codecType) | unique), colours: (map(.colour) | unique)}]' capabilities.json
```

Pass when each lens's FourCCs equal its camera's minus `jpeg`, `jxlc`, `muxa`, and colours agree (sRGB = Rec. 709, P3_D65 = P3, HLG_BT2020 = HLG). Record any difference in the PR.
- [ ] Record settings on each lens shows only what that lens reported.

---

### Task 8: Photo capture

**Files:**
- Create in `DuoCam/Capture/`: `PhotoCapturer.swift`, `PhotoCaptureDelegate.swift`, `PhotoSettingsPlan.swift`, `PhotoCaptureError.swift`, `CaptureStore.swift`, `CaptureStoreError.swift`, `CaptureFileKind.swift`
- Modify: `DuoCam/Capture/CameraSession.swift`, `DuoCam/App/CameraModel.swift`
- Test: `DuoCamTests/PhotoCaptureTests.swift`

**Interfaces:**
- Consumes: Task 6 `CameraSession`; Task 2 `PhotoSelection`; Task 1 `PhotoFormat`.
- Produces:

```swift
enum CaptureFileKind: String, Sendable { case dng = "DNG", heic = "HEIC", mov = "MOV", sidecar = "json" }
@MainActor final class CaptureStore {
    static func appDefault() throws(CaptureStoreError) -> CaptureStore   // Documents/Captures, created if missing
    init(directory: URL) throws(CaptureStoreError); let directory: URL
    func reserveSequence() -> Int                                        // never reused in this run
    func url(sequence: Int, kind: CaptureFileKind) -> URL
    static func fileName(sequence: Int, kind: CaptureFileKind) -> String // "DC_0001.DNG"
    static func nextSequence(existingNames: [String]) -> Int
}
struct PhotoSettingsPlan: Equatable, Sendable { let rawPixelFormat: OSType?; let wantsProcessedHEIF: Bool; let prioritizesSpeed: Bool
    static func make(format: PhotoFormat, availableRawFormats: [OSType], isBayer: (OSType) -> Bool, zoomFactor: Double) throws(PhotoCaptureError) -> PhotoSettingsPlan }
enum PhotoCaptureError: Error, CustomStringConvertible, Equatable { case rawNeedsUnitZoom(zoom: Double), rawUnavailable, noPhotoData, writeFailed(path: String, reason: String), captureFailed(reason: String) }
extension CameraSession { func capturePhoto(format: PhotoFormat, dngURL: URL, heicURL: URL) async throws(PhotoCaptureError) -> [URL] }
```

RAW takes the first Bayer format in `availableRawPhotoPixelFormatTypes` (production `isBayer` is `AVCapturePhotoOutput.isBayerRAWPixelFormat`), `rawFileType = .dng`, `.speed` prioritization, and requires `videoZoomFactor == 1.0` (capture sheet, Bayer RAW rules). HEIF uses `.hevc` and `.balanced`. `maxPhotoDimensions` follows `PhotoSelection.megapixels` before `startRunning`. Files come from `fileDataRepresentation()`; RAW and HEIF of one press share a number. `lastCapture` becomes the HEIC if present, else the DNG. A failure sets `notice` to "Photo not saved." and logs the error description.

- [ ] **Step 1: Write the failing tests**

```swift
@Suite struct PhotoCaptureTests {
    let bayer = kCVPixelFormatType_14Bayer_BGGR
    @Test func namesAndSequence() {
        #expect(CaptureStore.fileName(sequence: 1, kind: .dng) == "DC_0001.DNG"); #expect(CaptureStore.fileName(sequence: 12345, kind: .mov) == "DC_12345.MOV")
        #expect(CaptureStore.nextSequence(existingNames: ["DC_0001.DNG", "DC_0001.HEIC", "DC_0002.MOV", "DC_0002.json", "sweep-2026-11-09-143005.json", "notes.txt"]) == 3)
        #expect(CaptureStore.nextSequence(existingNames: []) == 1)
    }
    @Test func rawRules() {
        #expect(throws: PhotoCaptureError.rawNeedsUnitZoom(zoom: 2)) { try PhotoSettingsPlan.make(format: .raw, availableRawFormats: [bayer], isBayer: { $0 == bayer }, zoomFactor: 2) }
        #expect(throws: PhotoCaptureError.rawUnavailable) { try PhotoSettingsPlan.make(format: .rawPlusHEIF, availableRawFormats: [], isBayer: { _ in false }, zoomFactor: 1) }
    }
    @Test func plans() throws {
        #expect(try PhotoSettingsPlan.make(format: .rawPlusHEIF, availableRawFormats: [bayer], isBayer: { $0 == bayer }, zoomFactor: 1)
                == PhotoSettingsPlan(rawPixelFormat: bayer, wantsProcessedHEIF: true, prioritizesSpeed: true))
        #expect(try PhotoSettingsPlan.make(format: .heif, availableRawFormats: [bayer], isBayer: { $0 == bayer }, zoomFactor: 2)
                == PhotoSettingsPlan(rawPixelFormat: nil, wantsProcessedHEIF: true, prioritizesSpeed: false))
    }
}
```

- [ ] **Step 2: Run to see them fail** — `scripts/test.sh PhotoCaptureTests`.
- [ ] **Step 3: Implement the files; `capturePressed` in photo mode reserves a number and captures.**
- [ ] **Step 4: Run all tests.**
- [ ] **Step 5: Commit** — `git add DuoCam DuoCamTests && git commit -m "feat: capture RAW DNG and HEIF photos"`

**On the device:**
- [ ] 1x, RAW + HEIF 48 MP: one press writes `DC_000n.DNG` and `.HEIC`; both open in Files; on the Mac `mdls -name kMDItemPixelWidth -name kMDItemPixelHeight` on the DNG shows the sensor size.
- [ ] 0.5x RAW writes a DNG. On 2x the RAW chips read "RAW needs the 0.5x or 1x lens." and HEIF works. Front lenses: HEIF works; note whether either reports Bayer RAW.
- [ ] Ten quick presses give ten distinct numbers, no overwrite, no crash.

---

### Task 9: Video recording, sidecar, audio and meters

**Files:**
- Create in `DuoCam/Capture/`: `MovieRecorder.swift`, `MovieOutputSettings.swift`, `RecordingOutcome.swift`, `StopReason.swift`, `RecordingResult.swift`, `RecordingError.swift`, `ClipInspector.swift`, `ClipFacts.swift`, `ClipSidecar.swift`, `AudioMeter.swift`, `FreeSpace.swift`
- Modify: `DuoCam/Capture/CameraSession.swift`, `DuoCam/Capture/CaptureAccess.swift`, `DuoCam/App/CameraModel.swift`
- Test: `DuoCamTests/RecordingTests.swift` (suites below)

**Interfaces:**
- Consumes: Task 3 `DataRateEstimator`; Task 6 `CameraSession`, `CaptureAccess`; Task 8 `CaptureStore`.
- Produces:

```swift
struct MovieOutputSettings: Equatable, Sendable { let codecType: String; let averageBitRate: Int?
    static func make(for option: VideoOption, supportedKeys: [String]) -> MovieOutputSettings }
    // bitrate = Int(DataRateEstimator.megabitsPerSecond * 1e6), only for tiers and only when supportedKeys contains AVVideoCompressionPropertiesKey
enum StopReason: Sendable, Equatable { case storageFull, interrupted, maximumFileSize, maximumDuration, other(code: Int) }
enum RecordingOutcome: Sendable, Equatable { case completed, stopped(StopReason, isPlayable: Bool), failed(String)
    init(error: NSError?); var notice: String? { get } }      // AVErrorRecordingSuccessfullyFinishedKey decides isPlayable
struct RecordingResult: Sendable { let url: URL; let option: VideoOption; let outcome: RecordingOutcome; let sidecar: ClipSidecar? }
struct ClipFacts: Codable, Sendable, Equatable { let codecFourCC: String; let width: Int; let height: Int; let nominalFrameRate: Double; let durationSeconds: Double
    let frameCount: Int; let droppedFrames: Int; let colour: ColourMode?; let megabitsPerSecond: Double; let hasAudio: Bool }
struct ClipSidecar: Codable, Sendable { let requested: VideoOption; let actual: ClipFacts?; let outcome: String; let recordedAt: Date; let error: String? }
enum ClipInspector {
    static func inspect(url: URL, requestedFrameRate: Int) async throws(RecordingError) -> ClipFacts   // frames by stepping makeSampleCursorAtFirstSampleInDecodeOrder()
    static func droppedFrames(durationSeconds: Double, frameRate: Int, frameCount: Int) -> Int          // max(0, round(duration * rate) - count)
    static func colour(primaries: String?, transfer: String?, log: String?) -> ColourMode? }
enum AudioMeter { static func level(decibels: Float) -> Double }   // -60 dB -> 0, 0 dB -> 1, linear, clamped
enum FreeSpace { static func availableBytes() -> Int64 }            // volumeAvailableCapacityForImportantUsage of Documents
extension CameraSession {
    nonisolated var recordings: AsyncStream<RecordingResult> { get }   // backed by a nonisolated let declared in the actor body
    func startRecording(option: VideoOption, url: URL, minFreeBytes: Int64) throws(RecordingError)
    func stopRecording(); func audioLevels() -> [Double] }     // audioChannels averagePowerLevel of the movie output's audio connection
extension CameraModel { func recordingDidFinish(_ result: RecordingResult) }
```

Notes:
- `MovieRecorder` wraps `AVCaptureMovieFileOutput`: `minFreeDiskSpaceLimit` = the reserve, or free space minus N MB with `-freeSpaceMarginMB N` (to test the storage path); settings via `setOutputSettings(_:for:)` with the dictionary built only there; `videoRotationAngle` from `RotationCoordinator(device:previewLayer: nil)` at start; after `fileOutput(_:didFinishRecordingTo:from:error:)` it inspects the clip, writes `DC_000n.json` beside it, and yields a `RecordingResult`.
- The SDK comments `AVVideoAverageBitRateKey` as "H.264 only"; the measured `megabitsPerSecond` in the sidecar is how HEVC tiers are checked.
- A default-microphone input is added only when `CaptureAccess.recordsSound`. Meters poll `audioLevels()` 10 times a second; with no audio input they stay empty.
- Colour: log `kCMFormatDescriptionLogTransferFunction_AppleLog2` / `_AppleLog` -> appleLog2 / appleLog; transfer `ITU_R_2100_HLG` -> hlg; primaries `P3_D65` -> p3; primaries and transfer `ITU_R_709_2` -> rec709; otherwise nil.
- Notices: completed nil; storageFull "Recording stopped. Storage is full. Clip saved."; interrupted "Recording stopped. The camera was interrupted. Clip saved."; any not-playable stop or failure "Recording failed. The clip could not be saved."; when `droppedFrames > 0` and no other notice, "DC_0002 dropped 5 frames.".
- `capturePressed` in video mode reserves a number and starts, or stops.

- [ ] **Step 1: Write the failing tests**

```swift
@Suite struct MovieOutputSettingsTests {
    @Test func bitrateOnlyForTiersAndOnlyWhenAllowed() {
        let uhd = Resolution.named(width: 3840, height: 2160), keys = [AVVideoCodecKey, AVVideoCompressionPropertiesKey]
        let hevc = VideoOption(lensID: "w", codec: VideoCodec(family: .hevc, quality: "Max", codecType: "hvc1", bitrateTier: .max), resolution: uhd, frameRate: 30, colour: .rec709)
        #expect(MovieOutputSettings.make(for: hevc, supportedKeys: keys) == MovieOutputSettings(codecType: "hvc1", averageBitRate: 44_789_760))
        #expect(MovieOutputSettings.make(for: hevc, supportedKeys: [AVVideoCodecKey]).averageBitRate == nil)
        let hq = VideoOption(lensID: "w", codec: VideoCodec(family: .proRes, quality: "422 HQ", codecType: "apch", bitrateTier: nil), resolution: uhd, frameRate: 30, colour: .appleLog2)
        #expect(MovieOutputSettings.make(for: hq, supportedKeys: keys).averageBitRate == nil)
    }
}
@Suite struct RecordingOutcomeTests {
    func error(_ code: AVError.Code, finished: Bool) -> NSError {
        NSError(domain: AVFoundationErrorDomain, code: code.rawValue, userInfo: [AVErrorRecordingSuccessfullyFinishedKey: finished])
    }
    @Test func diskFullStopsCleanlyAndKeepsPlayableFile() {
        let outcome = RecordingOutcome(error: error(.diskFull, finished: true))
        #expect(outcome == .stopped(.storageFull, isPlayable: true)); #expect(outcome.notice == "Recording stopped. Storage is full. Clip saved.")
    }
    @Test func interruptionFinalizesFile() {
        #expect(RecordingOutcome(error: error(.sessionWasInterrupted, finished: true)) == .stopped(.interrupted, isPlayable: true))
        #expect(RecordingOutcome(error: error(.sessionWasInterrupted, finished: false)).notice == "Recording failed. The clip could not be saved.")
        #expect(RecordingOutcome(error: nil) == .completed)
    }
}
@Suite struct ClipInspectorTests {
    @Test func droppedFramesNeverNegative() {
        #expect(ClipInspector.droppedFrames(durationSeconds: 3, frameRate: 30, frameCount: 90) == 0); #expect(ClipInspector.droppedFrames(durationSeconds: 3, frameRate: 30, frameCount: 85) == 5)
        #expect(ClipInspector.droppedFrames(durationSeconds: 3, frameRate: 30, frameCount: 92) == 0); #expect(ClipInspector.droppedFrames(durationSeconds: 2, frameRate: 24, frameCount: 47) == 1)
    }
    @Test func colourFromFormatExtensions() {
        #expect(ClipInspector.colour(primaries: nil, transfer: nil, log: kCMFormatDescriptionLogTransferFunction_AppleLog2 as String) == .appleLog2)
        #expect(ClipInspector.colour(primaries: kCMFormatDescriptionColorPrimaries_ITU_R_2020 as String, transfer: kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String, log: nil) == .hlg)
        #expect(ClipInspector.colour(primaries: kCMFormatDescriptionColorPrimaries_ITU_R_709_2 as String, transfer: kCMFormatDescriptionTransferFunction_ITU_R_709_2 as String, log: nil) == .rec709)
        #expect(ClipInspector.colour(primaries: nil, transfer: nil, log: nil) == nil)
    }
}
@Suite struct CaptureAccessTests {
    @Test func microphoneDeniedStillRecordsVideoWithoutSound() {
        let access = CaptureAccess(camera: .authorized, microphone: .denied)
        #expect(access.canUseCamera); #expect(!access.recordsSound)
    }
}
@MainActor @Suite struct CameraModelRecordingTests {
    @Test func interruptionResetsUI() throws {
        let model = CameraModel(config: .parse(["app", "-recording", "on"]), capabilities: try Fixture.load(), isSimulator: true, defaults: try Fixture.freshDefaults())
        let option = try #require(model.currentVideoOption)
        model.recordingDidFinish(RecordingResult(url: URL(filePath: "/tmp/DC_0002.MOV"), option: option, outcome: .stopped(.interrupted, isPlayable: true), sidecar: nil))
        #expect(!model.isRecording && model.recordingStart == nil)
        #expect(model.notice == "Recording stopped. The camera was interrupted. Clip saved."); #expect(model.lastCapture?.lastPathComponent == "DC_0002.MOV")
    }
}
@Suite struct AudioMeterTests {
    @Test func scale() {
        #expect(AudioMeter.level(decibels: -60) == 0); #expect(AudioMeter.level(decibels: -30) == 0.5)
        #expect(AudioMeter.level(decibels: -90) == 0); #expect(AudioMeter.level(decibels: 3) == 1)
    }
}
```

- [ ] **Step 2: Run to see them fail** — `scripts/test.sh RecordingOutcomeTests` (the file does not compile yet).
- [ ] **Step 3: Implement the files to the notes above.**
- [ ] **Step 4: Run all tests** — `scripts/test.sh`. Expected: `** TEST SUCCEEDED **`.
- [ ] **Step 5: Commit** — `git add DuoCam DuoCamTests && git commit -m "feat: record video through the movie output with sidecar, audio and meters"`

**On the device:**
- [ ] HEVC High 4K 30 Rec. 709 on 1x for 10 s: `DC_000n.MOV` and `.json` in Files; sidecar shows `hvc1`, 3840 x 2160, about 30 fps, `droppedFrames` 0, `hasAudio` true, `megabitsPerSecond` near 27. Repeat at Max and Low; if all three measure the same, the bitrate is ignored for HEVC: note it in the PR.
- [ ] One ProRes and one Apple Log 2 option, if reported: sidecar `actual.colour` matches the request.
- [ ] Meters move with speech. Microphone denied in Settings: the clip records, `hasAudio` is false.
- [ ] Launch with `-freeSpaceMarginMB 300` (Xcode scheme argument) and record ProRes 4K until it stops itself: "Recording stopped. Storage is full. Clip saved." and the clip plays.
- [ ] While recording, one at a time: swipe home; fold or unfold; take a phone call. Each clip plays, has a sidecar, the record button returns to idle and the notice says the clip was saved.
- [ ] Dolby Vision check: record HLG HEVC and inspect on the Mac (QuickTime Inspector or `mediainfo`) for Dolby Vision metadata. Note the answer in the PR.

---

### Task 10: Camera Control and live readouts

**Files:**
- Create in `DuoCam/Capture/`: `CaptureAction.swift`, `CameraControlPlan.swift`, `SystemControlKind.swift`, `CameraControlsDelegate.swift`, `LiveReadouts.swift`, `ReadoutFormatter.swift`, `Timecode.swift`
- Modify: `DuoCam/Capture/CameraSession.swift`, `DuoCam/App/CameraModel.swift`, `DuoCam/UI/CameraRootView.swift`, `DuoCam/UI/TopReadoutBar.swift`, `DuoCam/UI/FoldedVerticalView.swift`, `DuoCam/UI/TimecodeReadout.swift`
- Test: `DuoCamTests/ControlsAndReadoutsTests.swift`

**Interfaces:**
- Consumes: Task 6 `CameraSession`; `CameraModel.capturePressed` from Tasks 8 and 9.
- Produces:

```swift
enum CaptureAction: Equatable, Sendable { case takePhoto, startRecording, stopRecording
    static func forEvent(phase: AVCaptureEventPhase, mode: CaptureMode, isRecording: Bool) -> CaptureAction? }   // only .ended acts
enum SystemControlKind: Sendable, Equatable { case zoom, exposureBias }
enum CameraControlPlan { static func kinds(supportsControls: Bool, mode: CaptureMode, photoFormat: PhotoFormat) -> [SystemControlKind] }
struct LiveReadouts: Sendable, Equatable { var iso: Float?; var shutterSeconds: Double?; var kelvin: Float?; var tint: Float?; var exposureBias: Float? }
enum ReadoutFormatter { static func shutter(_ s: Double?) -> String; static func iso(_ v: Float?) -> String; static func kelvin(_ v: Float?) -> String
    static func tint(_ v: Float?) -> String; static func bias(_ v: Float?) -> String }   // nil -> "--"
enum Timecode { static func string(elapsed: TimeInterval, frameRate: Int) -> String }   // HH:MM:SS:FF
extension CameraSession { func installSystemControls(_ kinds: [SystemControlKind]); func currentReadouts() -> LiveReadouts }
extension CameraModel { func handleCaptureEvent(phase: AVCaptureEventPhase) }
```

`CameraRootView` adds `.onCameraCaptureEvent(isEnabled: model.canCapture) { model.handleCaptureEvent(phase: $0.phase) }`. `installSystemControls` runs after every `configure`: remove existing controls; for each kind create `AVCaptureSystemZoomSlider(device:)` or `AVCaptureSystemExposureBiasSlider(device:)`; add it when `supportsControls` and `canAddControl`; set `setControlsDelegate(_:queue:)` with a `CameraControlsDelegate` on the session queue ("A controls delegate must be specified for controls to become active"). RAW photo formats get no zoom slider because Bayer RAW needs zoom 1.0. Readouts read `iso`, `exposureDuration`, `exposureTargetBias` and `temperatureAndTintValues(for: deviceWhiteBalanceGains)`, polled 4 times a second while ready; FPS shows the selection's rate. Photo layout shows SHUTTER, ISO, EV, WB.

- [ ] **Step 1: Write the failing tests**

```swift
@Suite struct ControlsAndReadoutsTests {
    @Test func onlyEndedPhaseActs() {
        #expect(CaptureAction.forEvent(phase: .began, mode: .photo, isRecording: false) == nil)
        #expect(CaptureAction.forEvent(phase: .cancelled, mode: .video, isRecording: true) == nil)
        #expect(CaptureAction.forEvent(phase: .ended, mode: .photo, isRecording: false) == .takePhoto)
        #expect(CaptureAction.forEvent(phase: .ended, mode: .video, isRecording: false) == .startRecording)
        #expect(CaptureAction.forEvent(phase: .ended, mode: .video, isRecording: true) == .stopRecording)
    }
    @Test func controlPlan() {
        #expect(CameraControlPlan.kinds(supportsControls: false, mode: .video, photoFormat: .heif) == [])
        #expect(CameraControlPlan.kinds(supportsControls: true, mode: .video, photoFormat: .raw) == [.zoom, .exposureBias])
        #expect(CameraControlPlan.kinds(supportsControls: true, mode: .photo, photoFormat: .rawPlusHEIF) == [.exposureBias])
        #expect(CameraControlPlan.kinds(supportsControls: true, mode: .photo, photoFormat: .heif) == [.zoom, .exposureBias])
    }
    @Test func formatting() {
        #expect(ReadoutFormatter.shutter(1.0 / 60) == "1/60"); #expect(ReadoutFormatter.shutter(0.5) == "1/2"); #expect(ReadoutFormatter.shutter(2.5) == "2.5s")
        #expect(ReadoutFormatter.shutter(nil) == "--"); #expect(ReadoutFormatter.iso(400.4) == "400")
        #expect(ReadoutFormatter.kelvin(5612) == "5600K"); #expect(ReadoutFormatter.kelvin(5630) == "5650K")
        #expect(ReadoutFormatter.tint(3.6) == "+4"); #expect(ReadoutFormatter.tint(-2.2) == "-2"); #expect(ReadoutFormatter.tint(0.3) == "0")
        #expect(ReadoutFormatter.bias(0) == "0.0"); #expect(ReadoutFormatter.bias(0.333) == "+0.3")
        #expect(Timecode.string(elapsed: 42.5, frameRate: 30) == "00:00:42:15"); #expect(Timecode.string(elapsed: 3661, frameRate: 24) == "01:01:01:00")
    }
}
```

- [ ] **Step 2: Run to see them fail** — `scripts/test.sh ControlsAndReadoutsTests`.
- [ ] **Step 3: Implement the files listed.**
- [ ] **Step 4: Run all tests, then `scripts/shot.sh t10-video-h -orientation landscape`** — FPS reads "30", live values `--`.
- [ ] **Step 5: Commit** — `git add DuoCam DuoCamTests docs/screenshots/p1a && git commit -m "feat: add Camera Control capture, system controls and live readouts"`

**On the device:**
- [ ] Note whether the Duo has a Camera Control button (spec open risk 3). If so, a full press takes a photo, or starts and stops recording; the on-screen button still works.
- [ ] Light press shows the system zoom and exposure sliders; with a RAW format only exposure.
- [ ] ISO, shutter, WB and tint change between a bright window and a dark corner.

---

### Task 11: Honest states and the last capture

**Files:**
- Create: `DuoCam/App/StatusText.swift`, `DuoCam/App/RemainingTime.swift`, `DuoCam/App/ViewfinderStatus.swift`, `DuoCam/UI/StatusOverlay.swift`, `DuoCam/UI/LibraryThumbnail.swift`
- Modify: `DuoCam/App/CameraModel.swift`, `DuoCam/UI/ViewfinderArea.swift`, `DuoCam/UI/BottomBar.swift`, `DuoCam/UI/FoldedVerticalVideoView.swift`, `DuoCam/UI/StripToolbar.swift`, `DuoCam/Capture/CaptureStore.swift`
- Test: `DuoCamTests/StatusTextTests.swift`

**Interfaces:**
- Consumes: `CameraPhase`, `CaptureAccess`, `PressureLevel`, `DataRateEstimator`, `CaptureStore`, the notices from Tasks 6 and 9.
- Produces:

```swift
struct RemainingTime: Equatable, Sendable { let text: String; let isWarning: Bool }
struct ViewfinderStatus: Equatable, Sendable { let message: String; let offersSettings: Bool }
enum StatusText {
    static func viewfinder(_ phase: CameraPhase) -> ViewfinderStatus?
    static func pressure(_ level: PressureLevel, isThermal: Bool) -> String?
    static func bottomNotice(access: CaptureAccess, minutesRemaining: Int, pressure: String?, notice: String?) -> String?
    static func remaining(minutes: Int) -> RemainingTime
}
extension CaptureStore { static func latestCaptureName(_ names: [String]) -> String?; func latestCapture() -> URL? }
```

Copy: `.scanning` "Reading camera formats…"; `.cameraDenied` "Camera access is off." with an "Open Settings" button (`UIApplication.openSettingsURLString`); `.cameraRestricted` "Camera access is restricted on this iPhone."; `.failed(m)` m; `.ready` and `.simulator` nil. Pressure, P = "The phone is hot." when thermal else "The phone is under heavy load.": serious "P Frame rate may drop.", critical "P Recording may stop.", shutdown "Camera stopped to protect the phone.", nominal and fair nil. Bottom notice precedence: "Storage full" (0 minutes), then pressure, then "No microphone access" (tap opens Settings), then the transient notice. Remaining: "21 min", warning below 5 minutes, "Storage full" at 0, and the record button is disabled at 0. Latest capture: highest sequence; within it HEIC over DNG, MOV over json; other names ignored. `LibraryThumbnail` shows a `QLThumbnailGenerator` thumbnail of the latest capture, or the disabled `photo.on.rectangle` symbol when none; a tap opens `.quickLookPreview`. In the Simulator each `-state` value drives the matching state.

- [ ] **Step 1: Write the failing tests**

```swift
@Suite struct StatusTextTests {
    @Test func viewfinderStates() {
        #expect(StatusText.viewfinder(.scanning) == ViewfinderStatus(message: "Reading camera formats…", offersSettings: false))
        #expect(StatusText.viewfinder(.cameraDenied) == ViewfinderStatus(message: "Camera access is off.", offersSettings: true))
        #expect(StatusText.viewfinder(.ready) == nil)
    }
    @Test func pressureCopy() {
        #expect(StatusText.pressure(.serious, isThermal: true) == "The phone is hot. Frame rate may drop.")
        #expect(StatusText.pressure(.critical, isThermal: false) == "The phone is under heavy load. Recording may stop.")
        #expect(StatusText.pressure(.fair, isThermal: true) == nil)
    }
    @Test func bottomNoticePrecedence() {
        let micOff = CaptureAccess(camera: .authorized, microphone: .denied), micOn = CaptureAccess(camera: .authorized, microphone: .authorized)
        #expect(StatusText.bottomNotice(access: micOff, minutesRemaining: 0, pressure: "P", notice: "N") == "Storage full")
        #expect(StatusText.bottomNotice(access: micOff, minutesRemaining: 20, pressure: "P", notice: "N") == "P")
        #expect(StatusText.bottomNotice(access: micOff, minutesRemaining: 20, pressure: nil, notice: "N") == "No microphone access")
        #expect(StatusText.bottomNotice(access: micOn, minutesRemaining: 20, pressure: nil, notice: "N") == "N")
    }
    @Test func remainingAndLatest() {
        #expect(StatusText.remaining(minutes: 4) == RemainingTime(text: "4 min", isWarning: true))
        #expect(StatusText.remaining(minutes: 0) == RemainingTime(text: "Storage full", isWarning: true))
        #expect(CaptureStore.latestCaptureName(["DC_0001.DNG", "DC_0001.HEIC", "DC_0002.MOV", "DC_0002.json", "sweep-x.json"]) == "DC_0002.MOV")
        #expect(CaptureStore.latestCaptureName(["DC_0003.DNG", "DC_0003.HEIC"]) == "DC_0003.HEIC"); #expect(CaptureStore.latestCaptureName([]) == nil)
    }
}
```

- [ ] **Step 2: Run to see them fail** — `scripts/test.sh StatusTextTests`.
- [ ] **Step 3: Implement the files listed.**
- [ ] **Step 4: Run all tests, then screenshot every state**

```bash
for s in scanning cameraDenied micDenied lowStorage storageFull pressure; do scripts/shot.sh "t11-$s-h" -orientation landscape -mode video -state "$s"; done
scripts/shot.sh t11-cameraDenied-v -orientation portrait -mode photo -state cameraDenied
```

Pass when each shot shows exactly its copy: in the viewfinder area for scanning and camera denied (with "Open Settings"), in the bottom bar for the rest; nothing covers the picture when horizontal; the record button is disabled for storage full and camera denied.

- [ ] **Step 5: Commit** — `git add DuoCam DuoCamTests docs/screenshots/p1a && git commit -m "feat: add honest capture states and the last-capture thumbnail"`

**On the device:**
- [ ] Camera denied in Settings: "Camera access is off."; "Open Settings" opens DuoCam's page. Microphone denied: video records and the bottom bar says "No microphone access".
- [ ] After a photo and a clip, the strip thumbnail shows the newest and opens it full screen.
- [ ] During a long 4K ProRes recording in warmth, note the first pressure notice and its level.

---

### Task 12: Format sweep and full device verification

**Files:**
- Create in `DuoCam/Capture/`: `FormatSweep.swift`, `SweepRow.swift`, `SweepStatus.swift`, `SweepReport.swift`; Create `DuoCam/Capability/FailedCombinations.swift`, `DuoCam/UI/SweepView.swift`
- Modify: `DuoCam/App/CameraModel.swift` (owns `sweep: FormatSweep?` and `failedCombinations`, forwards each `RecordingResult` while the sweep runs), `DuoCam/UI/FormatButton.swift` (long press opens `.sweep` in video mode; `isWarning` style), `DuoCam/UI/RecordSettingsSheet.swift` (`sweepCaption: String?` shown under the footer), `DuoCam/UI/CameraRootView.swift`
- Test: `DuoCamTests/FormatSweepTests.swift`, `DuoCamTests/FailedCombinationsTests.swift`

**Interfaces:**
- Consumes: Task 9 `startRecording`, `stopRecording`, `RecordingResult`, `ClipFacts`; Task 6 `configure`, `DeviceIdentity`; Task 8 `CaptureStore`.
- Produces:

```swift
enum SweepStatus: String, Codable, Sendable { case pass, fail }
struct SweepRow: Codable, Sendable, Equatable { let requested: VideoOption; let actual: ClipFacts?; let status: SweepStatus; let error: String?
    static func evaluate(requested: VideoOption, facts: ClipFacts?, error: String?) -> SweepRow }
struct SweepReport: Codable, Sendable { let startedAt: Date; let finishedAt: Date; let lensID: String; let osBuild: String; let modelIdentifier: String
    let cancelled: Bool; let rows: [SweepRow]
    static func fileName(for date: Date, timeZone: TimeZone) -> String   // "sweep-2026-11-09-143005.json"
    var summary: String { get } }                                         // "80 passed, 4 failed."
@MainActor @Observable final class FormatSweep {
    init(session: CameraSession, store: CaptureStore, lens: Lens, options: [VideoOption], keepsClips: Bool)
    private(set) var done: Int; let total: Int; private(set) var rows: [SweepRow]; private(set) var isRunning: Bool; private(set) var reportURL: URL?
    var progressText: String { get }   // "12 of 84"
    func run() async; func cancel(); func recordingDidFinish(_ result: RecordingResult)
}
nonisolated struct FailedCombinations: Codable, Sendable, Equatable {   // Application Support/DuoCam/failed-combinations.json
    var osBuild: String; var failedByLens: [String: [VideoOption]]
    static let caption = "This combination did not record in the last format sweep."
    static func load(directory: URL, osBuild: String) -> FailedCombinations          // empty when missing, unreadable or from another OS build
    func save(directory: URL) throws(CapabilityError)
    func replacing(lensID: String, with failed: [VideoOption]) -> FailedCombinations   // replaces that lens's list only
    func caption(for option: VideoOption?) -> String?                                 // caption when option is in the failed set, else nil
}
```

Wiring: `CameraModel.start(session:)` loads `FailedCombinations` with `DeviceIdentity.osBuild()` (the Simulator keeps it empty). When a sweep finishes or is cancelled, the model replaces the swept lens's list with the failed rows' `requested` options and saves. `failedCombinations.caption(for: currentVideoOption)` feeds `RecordSettingsSheet.sweepCaption` and `FormatButton.isWarning`, which uses the warning style of `RemainingTime.isWarning` (Task 11). Chips stay selectable.

Pass rule: no error; FourCC equals the request; dimensions equal in either orientation; nominal frame rate within 0.5; colour equal when the file reports one; duration at least 2.5 s. Failure text, first match: "Asked for apch, file has hvc1.", "Asked for 3840 x 2160, file has 1920 x 1080.", "Asked for 60 fps, file has 30.0 fps.", "Asked for Apple Log 2, file has Rec. 709.", "Clip is 1.2 s, expected 3 s.", or the error text. Dropped frames are reported per row, not a failure. The sweep configures each option, records 3 s, stops, awaits the result, deletes the clip unless `-keepSweepClips on` (keeping the sidecar), writes `Documents/Captures/sweep-<date>.json`, and restores the user's selection. Cancel finishes the current clip and writes the report with `cancelled: true`. Copy: title "Format sweep"; body "Records 3 seconds in each video format this lens reports, then saves a report in the Captures folder."; buttons "Start", "Cancel"; result "Done. 80 passed, 4 failed. Saved sweep-2026-11-09-143005.json." or "Cancelled after 12 of 84. Saved sweep-….json."; in the Simulator Start is disabled and the body reads "The sweep needs the camera.". Start is also disabled while recording.

- [ ] **Step 1: Write the failing tests**

```swift
@Suite struct FormatSweepTests {
    let ask = VideoOption(lensID: "wide", codec: VideoCodec(family: .proRes, quality: "422 HQ", codecType: "apch", bitrateTier: nil), resolution: .named(width: 3840, height: 2160), frameRate: 30, colour: .appleLog2)
    func facts(codec: String = "apch", w: Int = 3840, h: Int = 2160, colour: ColourMode? = .appleLog2, duration: Double = 3) -> ClipFacts {
        ClipFacts(codecFourCC: codec, width: w, height: h, nominalFrameRate: 29.97, durationSeconds: duration, frameCount: 90, droppedFrames: 0, colour: colour, megabitsPerSecond: 880, hasAudio: true)
    }
    @Test func matchingAndRotatedClipsPass() {
        #expect(SweepRow.evaluate(requested: ask, facts: facts(), error: nil).status == .pass)
        #expect(SweepRow.evaluate(requested: ask, facts: facts(w: 2160, h: 3840), error: nil).status == .pass)
    }
    @Test func mismatchesFailWithAReason() {
        #expect(SweepRow.evaluate(requested: ask, facts: facts(codec: "hvc1"), error: nil).error == "Asked for apch, file has hvc1.")
        #expect(SweepRow.evaluate(requested: ask, facts: facts(colour: .rec709), error: nil).error == "Asked for Apple Log 2, file has Rec. 709.")
        #expect(SweepRow.evaluate(requested: ask, facts: facts(duration: 1.2), error: nil).error == "Clip is 1.2 s, expected 3 s.")
        #expect(SweepRow.evaluate(requested: ask, facts: nil, error: "[MovieRecorder:start] Cannot record — {codec: apch}").status == .fail)
    }
    @Test func reportFileName() throws {
        let date = try #require(ISO8601DateFormatter().date(from: "2026-11-09T14:30:05Z"))
        #expect(SweepReport.fileName(for: date, timeZone: try #require(TimeZone(identifier: "UTC"))) == "sweep-2026-11-09-143005.json")
    }
}

@Suite struct FailedCombinationsTests {
    let bad = VideoOption(lensID: "wide", codec: VideoCodec(family: .proRes, quality: "422 HQ", codecType: "apch", bitrateTier: nil), resolution: .named(width: 3840, height: 2160), frameRate: 30, colour: .appleLog2)
    let good = VideoOption(lensID: "wide", codec: VideoCodec(family: .hevc, quality: "High", codecType: "hvc1", bitrateTier: .high), resolution: .named(width: 3840, height: 2160), frameRate: 30, colour: .rec709)
    @Test func captionAppearsAndDisappears() {
        let failed = FailedCombinations(osBuild: "B", failedByLens: [:]).replacing(lensID: "wide", with: [bad])
        #expect(failed.caption(for: bad) == "This combination did not record in the last format sweep.")
        #expect(failed.caption(for: good) == nil); #expect(failed.caption(for: nil) == nil)
        #expect(failed.replacing(lensID: "wide", with: []).caption(for: bad) == nil)
    }
    @Test func anotherOSBuildClearsTheSet() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try FailedCombinations(osBuild: "24B91", failedByLens: ["wide": [bad]]).save(directory: dir)
        #expect(FailedCombinations.load(directory: dir, osBuild: "24B91").caption(for: bad) != nil)
        #expect(FailedCombinations.load(directory: dir, osBuild: "24B114").caption(for: bad) == nil)
    }
}
```

- [ ] **Step 2: Run to see them fail** — `scripts/test.sh FormatSweepTests && scripts/test.sh FailedCombinationsTests`.
- [ ] **Step 3: Implement the files listed.**
- [ ] **Step 4: Run all tests, then `scripts/shot.sh t12-sweep-h -orientation landscape -screen sweep`** — Expected: pass; the sheet shows "Format sweep", "The sweep needs the camera." and a disabled Start.
- [ ] **Step 5: Commit** — `git add DuoCam DuoCamTests docs/screenshots/p1a && git commit -m "feat: add the format sweep and its report"`

**On the device: full P1a verification** (results and sweep reports go in the PR):
- [ ] Sweep on 1x, 0.5x, 2x and one front lens. Each writes a report; progress reads "n of N"; a mid-sweep Cancel writes one with `cancelled: true`. List every failed row with its reason. Then select one failed combination: Record settings reads "This combination did not record in the last format sweep." and the format summary shows the warning style; a passing combination shows neither. A second sweep of the same lens replaces the list.
- [ ] Review Focus 1: a second launch reads the cache (no "Reading camera formats…"). After the next iOS update the first launch must rescan; until then `CapabilityCacheTests.olderOSBuildTriggersRescan` is the evidence.
- [ ] Review Focus 2 to 5: the Task 9 storage, interruption and microphone checks pass, and on 1x with ProRes 4K selected, switching to a front lens moves the selection without a crash.
- [ ] Photos in every format on every lens that offers it open in Files and on the Mac.
- [ ] Strip: four items at the bottom of the left strip when horizontal; nothing under the camera hole; the Record settings close button sits in the strip.
- [ ] Files shows `Captures` with `DC_` files, sidecars and sweep reports.
- [ ] Written in the PR for later plans: the Dolby Vision answer, the outer front lens name, whether Camera Control exists, the first pressure level seen.
