# OpenCam Recorder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. All paths are relative to the worktree root, `/Users/tannerpham/CS Projects/DuoCam/.claude/worktrees/feat+camera-core`.

**Goal:** The Duo records ProRes 422 (Proxy, LT, 422, HQ) and a baked Log profile through a second, writer-based recorder, with honest labels, a live dropped-frame count and Apple's published data rates, while HEVC and H.264 stay on the system recorder.

**Architecture:** The model still talks to one `SessionConfigurator`; a `SessionConfiguration.recorder` value (`system` or `writer`), derived from the selected option, tells the session which outputs to attach, so a path switch is an ordinary configure behind the existing blur. The writer path is one full-size `AVCaptureVideoDataOutput` plus one `AVCaptureAudioDataOutput` feeding a queue-confined `WriterSink` that owns the `AVAssetWriter`; every decision it makes (first frame, drops, the stop policy, how a clip ends) is a pure value type, `WriterClipState`, tested with synthetic timing. Writer-only options are derived in memory from the scan's HLG entries, are never written to the cache, and are gated by `WriterSupport` so the phone lists only what its build can record.

**Tech Stack:** Swift 6 (MainActor default isolation), SwiftUI with system glass, AVFoundation, Core Image, Swift Testing. No new dependencies.

**Spec:** The owner, verbatim: "High quality video", "RAW video", "Apple Log 2", "Log 2 preview LUT in viewfinder", "Blackmagic-style codec/resolution choice". "I was only able to see HEVC and H.264, but we should be able to record in prores, set the codec, color compression, and choose color space formats, such as HLG, Log, ect..." "What other camera apps do is have handling for dropped frames, Each option for each codec should state what the estimated bitrate is, as well as the recording time available." "for the log recording, we can create two profiles, for a Apple Loglike and a Apple Log, which requires in RAW video mode for the full experience, or Apple Loglike for the other formats that have to have the compression baked in". "You should work to have those options available".

The controller's decisions, as planned (numbers point at "Read first"; bold marks a correction):

- A writer recorder beside the system movie output, used for ProRes and for Log; HEVC and H.264 in Rec. 709, P3 and HLG stay on the movie output. **The two paths never share a session configuration: the writer path detaches the movie output (4). A look in video is not built here, and looks are not offered on the writer path (5).**
- ProRes 422 Proxy, LT, 422, HQ at every size and rate where the scan shows a 10-bit HLG format, up to 60 fps, labelled as 4:2:0 from the camera in a 4:2:2 file. **ProRes in Rec. 709 comes from 8-bit frames, which neither check exercised, so it has its own switch (6).**
- Colour: Rec. 709, HLG, and one baked profile named "Log" with the detail "baked curve"; "Apple Log" is listed dimmed with its reason. **The viewfinder already shows the normal picture, so the inverse table is built and tested but never run on the viewfinder (3).**
- Dropped frames: live count, "When frames drop" setting, facts in the sidecar, a notice when a clip stopped for it. **Live only on the writer path: the system output has no drop signal on iOS (7).**
- Estimates stay on every Codec and Quality chip, ProRes from Apple's table. **The controller's example figure was the 24p row; the real change is at 720p (1).**
- Sound from the microphone already attached, the output's recommended settings, one writer queue, sync by presentation time.
- Nothing is promised that check 2 has not shown: unknown combinations are offered behind guards (drops counted, the stop policy, the clip always finalised) and listed under "To confirm on the phone".

## Read first: what the code, SDK and measurements change

1. **Decision 5's example is wrong; the table is still worth taking.** Apple's ProRes White Paper (April 2022, "Target Data Rates", pages 19 to 21, `https://www.apple.com/final-cut-pro/docs/Apple_ProRes.pdf`, read during planning; not in `docs/research`) lists 707 Mb/s for 422 HQ at 3840 x 2160 **24p**. The 30p row is 884, which the app's linear 881 (`OpenCam/Capability/DataRateEstimator.swift:88-100`) already matches within 0.4 percent. Linear scaling is wrong at 720p, where Apple's rows are higher per pixel: 422 HQ 720p30 is 110, the app says 98. Task 1 enters the table for 720p, 1080p and 2160p; sizes Apple does not list keep the linear estimate. A copy of the PDF sits at `/Users/tannerpham/.claude/projects/-Users-tannerpham-CS-Projects-DuoCam--claude-worktrees-feat-camera-core/a40a35e8-df92-4142-8ede-44bc730df0eb/tool-results/webfetch-1794483156476-ommwyz.pdf` if the controller wants it in `docs/research`.
2. **What the first check proved and did not.** `docs/research/duo-recorder-check-2026-11-12.json`: 20 trials, 1080p and 4K at 30 and 60, HEVC and four ProRes kinds, 0 frames not ready, 0 output drops, append mean 0.26 to 1.16 ms, worst 6.5 ms, heat nominal; hand-built `[codec, width, height]` settings accepted for all ProRes kinds; `availableVideoCodecTypesForAssetWriter(.mov)` is `hvc1, avc1, jpeg` (only `hvc1` at 4K 60). The scene was dark: 4K 60 422 HQ wrote 575 Mb/s against Apple's 1768, so headroom with a real scene is unknown. No preview, sound, render, or 8-bit source was tried. Check 2 (`-recorderCheck2` on `diag/recorder-check`) has not run.
3. **The "preview LUT" needs no work in the viewfinder.** The viewfinder is the preview layer (`OpenCam/UI/ViewfinderArea.swift:41`), fed by the camera's HLG picture. The bake touches only the frames going to the file. Running the inverse table over baked frames would add a second 4K render per frame to draw the picture the preview layer already shows. The inverse table is still defined, compiled and round-trip tested (Task 8) so a Log clip can be viewed normally later.
4. **Measured means exclusive.** Check 2 measures one video data output, one audio data output and a preview layer, with no movie output. So `recorder == .writer` attaches exactly that and detaches the movie output; `.system` is today's configuration unchanged (`CameraSession.swift:164-168`).
5. **Looks stay off the writer path.** A look's viewfinder needs the preview-sized `frameOutput` (`CameraSession.swift:364-394`); with the record output that is two video data outputs on one session, which nothing has measured. `LookAvailability` (`OpenCam/Capability/LookAvailability.swift:12-17`) gains the path.
6. **The 10-bit formats are HLG only.** Every `x420` format the check picked reports `supportedColorSpaces: ["HLG_BT2020"]`. ProRes in Rec. 709 therefore records 8-bit `420v` frames from an sRGB format. Same sink, different pixel format, never measured: `WriterSupport.proResSDR`.
7. **No live drop signal on the system path.** `AVCaptureFileOutput.delegate` is `API_UNAVAILABLE(ios)` (`AVCaptureFileOutput.h:50`). System clips keep today's count from the file read-back (`ClipInspector.swift:45-50`, notice at `CameraModel+Recording.swift:124-126`); "Stop recording" acts only on the writer path and the setting says so.
8. **A writer fails when the app goes to the background.** `AVAssetWriter.h:199`: status becomes failed "when the client app goes into the background" and the header points at a background task. `AVAssetWriter.h:281`: with `movieFragmentInterval` set, an interrupted file plays up to the last fragment. The plan uses both.
9. **Check 2's colour pass would clip Log.** It calls `LookRenderer.applyCube`, which looks the table up in Display P3 with `extrapolate = false` (`OpenCam/Render/LookRenderer.swift:83-91`). Good for timing, wrong for HLG highlights. Task 8 adds a table pass in a named colour space.
10. **The cache holds no bit depth.** `VideoOption` has lens, codec, size, rate, colour (`OpenCam/Capability/VideoOption.swift`). Because of 6, "this lens has an HEVC option in HLG at this size and rate" is the proof of a 10-bit format. On the phone's list (6,192 options) that derives 2,160 options; the 1x lens goes from 1,436 to 1,820.
11. **The deprecated writer calls.** `AVAssetWriter.add` (`AVAssetWriter.h:184-186`), `startWriting` (`:202-204`), `AVAssetWriterInput.isReadyForMoreMediaData` (`AVAssetWriterInput.h:158-160`), `expectsMediaDataInRealTime` (`:174-176`), `append` (`:259-261`) and the pixel buffer adaptor (`:549`) are deprecated in Swift for iOS 27. The replacement needs a `CMReadySampleBuffer` the delegate's buffer cannot become without a banned opt-out. `git show diag/recorder-check:OpenCam/Support/RecorderCheckSink.swift` and `RecorderCheck2Sink.swift` show the warning-free pattern this plan copies: the calls live in members marked `@available(iOS, deprecated: 27.0)`, reached through a non-deprecated protocol, with all writer state on one serial queue.
12. **Timestamps share one clock.** "All capture output sample buffer timestamps are on the synchronizationClock timebase" (`AVCaptureSession.h:605`), so video and sound are appended with their own presentation times and nothing is retimed.
13. **Tests that change on purpose.** `DataRateEstimatorTests.swift:9-13, :19-25` (881 becomes 884, 21 min becomes 20), `ColourModeTests.swift` (`.log` shares HLG's capture colour space), `CameraModelTests.swift:10` (`"Log 2"` becomes `"Apple Log 2"`), `LookAvailabilityTests`, `SavedStartTests`. `docs/screenshots/data-rate/` goes stale by 3 Mb/s.

## Global Constraints

- Branch `feat/recorder` from `feat/camera-ui-cleanup`. The camera core constraints apply: strict Swift 6 concurrency, no force unwraps or `try!`, one type per file, errors as `[Module:Function] Description — {context}`, no `@unchecked Sendable`, `nonisolated(unsafe)` or `@preconcurrency import`, no `Any` in our APIs, conventional commits, no attribution lines.
- Risk rule: with `recorder == .system` the session's outputs, the recording path and every notice are exactly as today. Everything new is reached only through a writer-only option.
- The phone never lists an option its build cannot record: `WriterSupport.shipped(isSimulator: false)` grows only in the task that makes the recording work (Tasks 6 and 9). The Simulator always derives everything.
- The capability cache, `CaptureCapabilities.currentScanVersion` (3) and the scan are untouched. Writer options exist only in memory.
- Writer state (the `AVAssetWriter`, its inputs, the adaptor, `WriterClipState`) is touched only inside `writerQueue.sync`. No queue waits on the session actor. `cancelWriting()` is never called once a frame has been written.
- Deprecated writer calls appear only in `WriterSink` members marked `@available(iOS, deprecated: 27.0, message:)`. The build has 0 warnings in Debug and Release.
- `LookRenderer.shared` stays the only `CIContext`. No pixel buffer leaves the queue it arrived on except through the writer.
- API facts only from the SDK headers (iPhoneOS27.2) or `docs/research` (git-ignored: cite, never commit). `docs/research` and `.superpowers` are never staged.
- Device SDK compile after Tasks 5, 6 and 9: `xcodebuild -project OpenCam.xcodeproj -scheme OpenCam -sdk iphoneos -destination generic/platform=iOS -derivedDataPath .build CODE_SIGNING_ALLOWED=NO build`, expected `** BUILD SUCCEEDED **`, 0 warnings.
- Copy: the strings in the tasks are final. Plain, sentence case, no em dashes.
- Simulator: only "OpenCam Dev" through `scripts/sim-udid.sh`. Tap tests: one action, wait 2 seconds, screenshot, look at it. Screenshots in `docs/screenshots/recorder/`, names `recorder-…`. The implementer reads every PNG.
- Nothing about the phone is claimed as verified. It goes on the device checklist.

## Review Focus

1. **A clip is lost or unplayable when recording ends any way but the stop button** (interruption, backgrounding, storage, a failed append, a stopped camera, two ends racing). Pinned by `WriterClipStateTests.everyEndAfterAFirstFrameFinishesAtTheLastFrameAndNeverCancels` and `aSecondEndDoesNothing` (Task 4) and `WriterSinkTests.anInterruptedClipIsStillAPlayableFile` (Task 6).
2. **Record settings offers something the phone cannot record:** a ProRes or Log chip at a size with no 10-bit format, or before the recorder exists. Pinned by `WriterOptionsTests.everyDerivedOptionHasAScannedHEVCOptionInHLGAtItsLensSizeAndRate` and `shippedSupportIsOnlyWhatIsWired` (Task 2).
3. **The selection and the session disagree about the path:** ProRes configured with the movie output, an old saved start adopted without the field, a switch that skips the configure. Pinned by `WriterOptionsTests.recorderFollowsTheOption` (Task 2), `CameraModelWriterTests.switchingPathsIsOneConfigureBehindTheBlur` and `SavedStartTests.aStartSavedBeforeRecorderPathsDecodesAsSystem` (Task 5).
4. **The count lies or the policy misfires:** one clip's count shows on the next, "Stop recording" stops twice or on a drop before anything was written, a drop storm floods the main actor. Pinned by `WriterClipStateTests.stopRecordingStopsOnceAtTheFirstDropAfterAFrameIsWritten` and `dropReportsComeAtOnceThenAtMostFourASecond` (Task 4) and `CameraModelWriterTests.aDropCountShowsOnlyForTheClipBeingRecorded` (Task 5).
5. **The Log file is wrong and nothing on screen shows it,** because the viewfinder shows the normal picture by design: clipped highlights, wrong curve, wrong tags. Pinned by `LookRendererTableTests.aTableInHLGKeepsPeakWhite` (Task 8) and `RecordingRenderTests.aGreyFrameComesOutAtTheCurveValue` and `theOutputIsTaggedBT2020WithTheRec709Curve` (Task 9).

---

### Task 1: ProRes data rates from Apple's table

**Files:** Create `OpenCam/Capability/ProResRateTable.swift`. Modify `OpenCam/Capability/DataRateEstimator.swift:19-20`. Test: create `OpenCamTests/ProResRateTableTests.swift`; modify `OpenCamTests/DataRateEstimatorTests.swift:9-13, :19-25`.

**Interfaces. Produces:**

```swift
nonisolated enum ProResRateTable {
    /// Apple's target rate in Mb/s; nil when Apple publishes no row for that kind, size or rate. Width and height in either order.
    static func megabitsPerSecond(quality: String, width: Int, height: Int, frameRate: Int) -> Double?
}
```

Table, Mb/s, columns 24, 25, 30, 50, 60 fps (source in "Read first" 1; the type's comment names the document, date and pages):

| Size | 422 Proxy | 422 LT | 422 | 422 HQ |
|---|---|---|---|---|
| 1280 x 720 | 18 19 23 38 45 | 41 42 51 84 101 | 59 61 73 122 147 | 88 92 110 184 220 |
| 1920 x 1080 | 36 38 45 76 91 | 82 85 102 170 204 | 117 122 147 245 293 | 176 184 220 367 440 |
| 3840 x 2160 | 145 151 182 303 363 | 328 342 410 684 821 | 471 492 589 983 1178 | 707 737 884 1475 1768 |

Rules. `DataRateEstimator.megabitsPerSecond` for `.proRes`: the cell; else the same size's 30 fps cell times `frameRate / 30` (48 fps); else today's `scaledProRes`, unchanged (sizes with no row, 4444 kinds). RAW, HEVC and H.264 are untouched.

- [ ] **Step 1: Failing tests.** `publishedCellsAreApples` (HQ 1080p30 220; HQ 4K30 884; HQ 4K24 707; 422 4K60 1178; Proxy 1080p24 36; LT 720p50 84; HQ 2160 x 3840 at 30 is 884). `aKindSizeOrRateWithNoRowHasNoCell` (HQ 1920 x 1440 30, "4444" 1080p30, HQ 4K48 all nil). In `DataRateEstimatorTests`: `proResUsesApplesTable` (HQ 4K30 == 884; HQ 720p30 == 110; HQ 4K48 within 0.001 of 1414.4; HQ 1920 x 1440 30 within 0.01 of 293.63, the unchanged linear figure); `remainingTimeKeepsTheReserve` now expects 6.63 GB per minute, 20 minutes at 141 GB, and the footer `"About 884 Mb/s, 6.6 GB per minute. 20 min left."`.
- [ ] **Step 2: Run and see fail.** `scripts/test.sh ProResRateTableTests`, exit 65.
- [ ] **Step 3: Implement.** A static dictionary keyed by pixel count and kind; Foundation only.
- [ ] **Step 4: Run** both suites, then all of `scripts/test.sh`.
- [ ] **Step 5: Commit.** `fix: take ProRes data rates from Apple's published table`

### Task 2: Writer-only options, the Log colour and the path

**Files:** Create `OpenCam/Capability/RecorderPath.swift`, `WriterSupport.swift`, `WriterOptions.swift`. Modify `ColourMode.swift`, `CaptureCapabilities.swift`, `CapabilityMapper.swift:6-15, :105-119` (make the four 422 codecs and `rowKey` reachable), `RecordSelectionResolver.swift:26-54`, `OpenCam/Capture/ClipInspector.swift:53-61`, `OpenCam/App/CameraModel.swift:270-276, :793`, `CameraModel+Scan.swift:27-29, :97-114`, `OpenCamApp.swift:35`. Test: create `OpenCamTests/WriterOptionsTests.swift`; modify `ColourModeTests`, `CameraModelTests.swift:10`, `ClipInspectorTests`, `ResolverEquivalenceTests`, `MainThreadCostTests`.

**Interfaces. Produces:**

```swift
nonisolated enum RecorderPath: String, Codable, Sendable { case system, writer }

nonisolated struct WriterSupport: OptionSet, Sendable {
    static let proRes: WriterSupport      // ProRes in HLG, from 10-bit frames
    static let proResSDR: WriterSupport   // ProRes in Rec. 709, from 8-bit frames
    static let log: WriterSupport         // the baked Log profile, ProRes and HEVC
    static let all: WriterSupport
    /// What this build can record. The Simulator records nothing and lists everything.
    static func shipped(isSimulator: Bool) -> WriterSupport   // device: [] in this task
}

nonisolated enum WriterOptions {
    static let maximumFrameRate = 60
    /// The one place a measured limit goes. True for everything up to 60 fps today.
    static func isOffered(quality: String, resolution: Resolution, frameRate: Int, colour: ColourMode) -> Bool
    /// Options only the writer records, grouped by lens in the mapper's row order; none the scan already holds.
    static func derived(from scanned: [VideoOption], support: WriterSupport) -> [VideoOption]
}

// ColourMode: `case log = "Log"` between `.hlg` and `.appleLog`. captureColorSpaceRawValue 2 (HLG BT.2020);
// init?(captureColorSpace:) never yields it. shortName: .log "Log", .appleLog "Apple Log", .appleLog2 "Apple Log 2".

extension CaptureCapabilities {
    var writerOptions: [VideoOption]   // stored, default [], absent from an explicit CodingKeys, so never encoded or decoded
    func withWriterOptions(_ support: WriterSupport) -> CaptureCapabilities
}

// RecordSelectionResolver
init(options: [VideoOption], writerOptions: [VideoOption] = [], lens: Lens?)
init(lensOptions: [VideoOption], writerOptions: [VideoOption] = [])   // the lens's scanned options, then its writer options
func recorder(for selection: RecordSelection) -> RecorderPath          // a Set<RecordOptionKey> lookup
```

Rules. For each lens and each (size, rate up to 60) with a scanned HEVC option in HLG: ProRes x four kinds in HLG (`.proRes`); the same in Log, plus HEVC in Log with the codecs of the scanned HEVC HLG options at that key (`.log`); ProRes x four kinds in Rec. 709 where a scanned HEVC Rec. 709 option also exists there (`.proResSDR`). No H.264, no P3, nothing above 60 fps. Scanned options come first in the resolver, so a tie settles on a system option. `ClipInspector.colour`: BT.2020 primaries with the Rec. 709 transfer is `.log`. Derivation runs off the main actor: `CameraModel.loadCache` returns `cache.load(...)?.withWriterOptions(.shipped(isSimulator: false))`, and the scan path derives in a `@concurrent` static before `adoptScan`; `adoptScan` still saves what it is given, which encodes without writer options. `OpenCamApp` derives the fixture with `.shipped(isSimulator: true)`. The sweep keeps `capabilities.videoOptions` (`CameraModel+Sweep.swift:8-11`), so it never records a writer option.

- [ ] **Step 1: Failing tests** (phone list from `Fixture.loadDuo()`). `thePhoneGainsProResAndLogWhereItHasHLG` (`.all` derives 2,160; the 1x lens 384: ProRes 288 split 96 each over HLG, Log, Rec. 709, HEVC 96 all Log; sizes 4K, 1920 x 1440, 1080p, 720p; top rate 60). `everyDerivedOptionHasAScannedHEVCOptionInHLGAtItsLensSizeAndRate`. `nothingScannedIsDerivedAgain` (bundled fixture, which already has ProRes in HLG). `supportGatesWhatIsDerived` (`[]` none; `[.proRes]` 540, all ProRes HLG; adding `.proResSDR` 1,080; `.all` 2,160). `shippedSupportIsOnlyWhatIsWired` (Simulator `.all`; device `[]`). `writerOptionsAreNeverEncoded` (`merged.encoded() == scanned.encoded()`; a cache saved from the merged value loads 6,192 options with no writer options; `currentScanVersion == 3`). `recorderFollowsTheOption` (1x: HEVC High 4K 30 Rec. 709 and HLG are `.system`; ProRes 422 HQ 4K 30 HLG and HEVC High 4K 30 Log are `.writer`). `ColourModeTests`: order is Rec. 709, P3, HLG, Log, Apple Log, Apple Log 2; `.log` reports raw value 2 and `ColourMode(captureColorSpace: 2) == .hlg`. `ClipInspectorTests`: 2020 primaries with 709 transfer is `.log`. `ResolverEquivalenceTests.theMergedListMatchesTheReference` (indexed resolver with writer options against the reference given `scanned + derived`, same assertions as `:29-55`). `MainThreadCostTests`: print `[perf] withWriterOptions on the phone's list` and re-run `bodyReads` and `lensFirstVisit` on a merged model under the same bound.
- [ ] **Step 2: Run and see fail.** `scripts/test.sh WriterOptionsTests`, exit 65.
- [ ] **Step 3: Implement.** One pass over the scanned options builds the HLG and Rec. 709 key sets per lens; the result is sorted with the mapper's `rowKey`.
- [ ] **Step 4: Run** the suites above, then all of `scripts/test.sh`.
- [ ] **Step 5: Commit.** `feat: derive the options only the writer records from the scan's HLG formats`

### Task 3: Record settings rows and copy

**Files:** Create `OpenCam/Capability/RecordRowText.swift`. Modify `OpenCam/UI/VideoRecordRows.swift:15-25`, `OpenCam/App/LaunchConfig.swift`, `OpenCam/Capability/CaptureCapabilities.swift`, `OpenCam/App/OpenCamApp.swift:35`. Test: create `OpenCamTests/RecordRowTextTests.swift`; modify `LaunchConfigTests`.

**Interfaces. Consumes:** Task 2. **Produces:**

```swift
nonisolated enum RecordRowText {
    static let logDetail = "baked curve"
    static let logNote = "Log records a flat picture made from HLG, for grading later. The curve cannot be removed from the file. The viewfinder shows the normal picture."
    static let appleLogUnavailable = "This iPhone does not record Apple Log, Apple Log 2 or RAW video."
    static let proResNote = "The camera delivers 4:2:0 colour. ProRes stores it in a 4:2:2 file and adds no colour detail."
    static let proResSDRNote = "The camera delivers 8-bit 4:2:0 colour in Rec. 709. ProRes stores it in a 10-bit 4:2:2 file and adds no detail."
    /// A row's chips as shown. Colour: Log carries `logDetail`; when no chip is Apple Log or Apple Log 2, a dimmed "Apple Log" chip with `appleLogUnavailable` is added last.
    static func chips(_ row: RecordRow, from chips: [Chip]) -> [Chip]
    /// The one line under a row: Colour with Log selected, `logNote`; Quality with ProRes selected, `proResNote` or `proResSDRNote`; otherwise the first dimmed chip's reason.
    static func line(_ row: RecordRow, chips: [Chip], selection: RecordSelection) -> String?
}
extension CaptureCapabilities { func asThePhoneScans() -> CaptureCapabilities }   // drops ProRes and RAW codecs and both Apple Log colours
// LaunchConfig: `var usesPhoneFormats = false`   // -formats phone (honoured in the Simulator only; scripted)
```

Rules. The resolver is not changed, so the equivalence tests keep their meaning; `VideoRecordRows` passes each row's chips and line through `RecordRowText`. With `-formats phone` the Simulator loads `bundledFixture().asThePhoneScans().withWriterOptions(.all)`, which is the phone's Record settings.

- [ ] **Step 1: Failing tests** (merged phone list, 1x). `logCarriesItsDetailAndAppleLogIsListedDimmed` (Colour for HEVC High 4K 30 Rec. 709: ids `Rec. 709, P3, HLG, Log, Apple Log`; Log available with detail "baked curve"; Apple Log unavailable with the reason). `appleLogIsNotAddedWhereTheLensHasIt` (bundled fixture: chips unchanged apart from Log's detail). `theLineUnderColour` (Log selected: `logNote`; HEVC Rec. 709: the Apple Log reason; ProRes HLG: "P3 is not available with ProRes."). `theLineUnderQuality` (ProRes HLG: `proResNote`; ProRes Rec. 709: `proResSDRNote`; HEVC: nil). `otherRowsAreUntouched`. `noStringHasAnEmDash`. `thePhoneFormatsFlagStripsWhatThePhoneLacks`. `LaunchConfigTests`: `-formats phone` sets the flag and `isScripted`.
- [ ] **Step 2: Run and see fail.** `scripts/test.sh RecordRowTextTests`, exit 65.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the suites, then all of `scripts/test.sh`.
- [ ] **Step 5: Tap test and screenshots,** portrait then landscape (`-orientation … -mode video -screen record -formats phone`; add `-cameraLook none` to open scrolled to the bottom): the sheet as it opens; after tapping ProRes; after tapping Log. Check: four Quality chips with both estimate lines whole, the ProRes line, the Log chip's detail, the Log line, the dimmed Apple Log chip and its reason. `recorder-rows-{portrait,landscape}-{hevc,prores,log}.png`.
- [ ] **Step 6: Commit.** `feat: label ProRes, Log and Apple Log in Record settings`

### Task 4: The writer clip's bookkeeping

**Files:** Create `OpenCam/Capture/DropPolicy.swift`, `DropReason.swift`, `DropFacts.swift`, `WriterEnd.swift`, `WriterClipState.swift`. Modify `StopReason.swift`, `RecordingOutcome.swift:36-55`. Test: create `OpenCamTests/WriterClipStateTests.swift`; modify `RecordingOutcomeTests`.

**Interfaces. Produces:**

```swift
nonisolated enum DropPolicy: String, Codable, Sendable, CaseIterable { case keepRecording, stopRecording }

/// Why a frame is missing from the file.
nonisolated enum DropReason: String, Codable, Sendable, CaseIterable {
    case late, outOfBuffers, discontinuity   // the output's drop callback (CMSampleBuffer.h:1762, :1773, :1784)
    case writerNotReady                      // delivered, but the writer input was not ready for it
    case behind                              // delivered more than one frame behind real time; not rendered, not written
    case renderFailed                        // the Log render or its buffer pool failed
    case other
    init(attachment: String?)                // the kCMSampleBufferAttachmentKey_DroppedFrameReason value
}

nonisolated struct DropFacts: Codable, Sendable, Equatable {
    var total = 0; var byReason: [String: Int] = [:]
    var framesDelivered = 0; var framesWritten = 0
    var audioBuffersNotWritten = 0; var stoppedRecording = false
}

nonisolated enum WriterEnd: Sendable, Equatable { case user, droppedFrames, storageFull, interrupted, cameraStopped, writerFailed, timedOut }

nonisolated struct WriterClipState: Sendable {
    enum VideoStep: Sendable, Equatable { case startAndWrite(at: CMTime), write, skip, ignore }
    enum Finish: Sendable, Equatable { case finish(endTime: CMTime), cancel, none }
    init(policy: DropPolicy, frameDuration: CMTime, minFreeBytes: Int64)
    mutating func video(pts: CMTime, duration: CMTime, arrival: Duration, isWriterReady: Bool) -> VideoStep
    mutating func videoWritten(_ isWritten: Bool, pts: CMTime, duration: CMTime) -> Finish   // false ends the clip as .writerFailed
    mutating func outputDropped(_ reason: DropReason) -> Finish
    mutating func renderFailed() -> Finish
    mutating func audio(pts: CMTime, isWriterReady: Bool) -> Bool
    mutating func storage(freeBytes: Int64) -> Finish
    mutating func end(_ end: WriterEnd) -> Finish
    mutating func dropCountToReport(arrival: Duration) -> Int?
    var isInFlight: Bool { get }; var end: WriterEnd? { get }; var facts: DropFacts { get }
}

// StopReason: add `.droppedFrames` and `.writerFailed`.
// RecordingOutcome: `init(writerEnd: WriterEnd, hasFrames: Bool, isReadable: Bool)`,
//   `static let droppedFramesStopNotice = "Recording stopped. A frame was dropped. Clip saved."`
```

Rules. `arrival` is time since the clip opened, on the sink's own clock. The first delivered frame starts the session at its own presentation time. A frame is `behind` when `arrival - firstArrival` exceeds `pts - firstPTS` by more than one frame duration: the rule check 2 measures as `framesDroppedRenderBusy`, applied to both paths. Sound before the first video frame is not written and is not a drop; sound the input was not ready for counts in `audioBuffersNotWritten`. "Stop recording" ends the clip at the first drop after a frame has been written; a drop before that only counts. Any end after a written frame is `.finish(endTime: last written pts + its duration)`; an end with nothing written is `.cancel`; a second end is `.none` and the first reason stands. `storage` ends the clip when free bytes are at or under the minimum. `dropCountToReport` returns the total at the first drop, then at most once per 250 ms of `arrival`, nil otherwise. Outcome: `.user` is `.completed`; `.droppedFrames`, `.storageFull`, `.interrupted` map to their `StopReason`; `.cameraStopped` and `.writerFailed` map to `.writerFailed`, whose notice is `incompleteNotice` when readable; `.timedOut` is `.stopped(.noResult, isPlayable: false)`; no frames or an unreadable file is `.failed` or not playable, as today's rows read.

- [ ] **Step 1: Failing tests.** `theFirstFrameStartsTheSessionAtItsOwnTime`. `soundBeforeTheFirstVideoFrameIsNotWritten`. `aFrameTheWriterIsNotReadyForIsADrop`. `aFrameMoreThanOneFrameBehindIsDropped` (30 fps: lag of exactly one frame writes, one frame and a millisecond skips with `behind`). `outputDropsAreCountedByReason` (`DropReason(attachment:)` for the three constants, nil and an unknown string). `keepRecordingNeverStopsForDrops`. `stopRecordingStopsOnceAtTheFirstDropAfterAFrameIsWritten` (a drop before the first frame counts and returns `.none`; the first after it returns `.finish`; later drops and frames return `.none` and `.ignore`; `facts.stoppedRecording`). `everyEndAfterAFirstFrameFinishesAtTheLastFrameAndNeverCancels` (each `WriterEnd`). `anEndBeforeAnyFrameCancels`. `aSecondEndDoesNothing`. `aFailedWriteEndsTheClipAsWriterFailed`. `lowStorageEndsTheClip`. `dropReportsComeAtOnceThenAtMostFourASecond` (1 at once; ten more within 100 ms give nil; at 250 ms, 11). `factsCountDeliveredAndWritten`. `RecordingOutcomeTests`: each mapping above and both new notices; no em dash.
- [ ] **Step 2: Run and see fail.** `scripts/test.sh WriterClipStateTests`, exit 65.
- [ ] **Step 3: Implement.** Foundation and CoreMedia only, all `nonisolated`.
- [ ] **Step 4: Run** the suites, then all of `scripts/test.sh`.
- [ ] **Step 5: Commit.** `feat: decide a writer clip's frames, drops and end in tested code`

### Task 5: The protocol surface, the fake and the model's routing

**Files:** Modify `OpenCam/Capture/SessionConfiguration.swift`, `SessionConfigurator.swift:16`, `SessionEvent.swift`, `OpenCam/Capability/LookAvailability.swift`, `OpenCam/Support/SavedStart.swift:41`, `OpenCam/App/CameraModel.swift:286-290, :931-996`, `CameraModel+Recording.swift:8-36, :97-104`, `CameraModel+Look.swift:20-27, :50-54`, `OpenCam/Capture/CameraSession.swift:599` (signature only; behaviour unchanged until Task 6), `OpenCamTests/FakeSessionConfigurator.swift:86-89`. Test: create `OpenCamTests/CameraModelWriterTests.swift`; modify `SavedStartTests`, `LookAvailabilityTests`, `ViewfinderChangeTests`, and the call sites of the fake's hook.

**Interfaces. Consumes:** Tasks 2 and 4. **Produces:**

```swift
// SessionConfigurator: one requirement changes, nothing is added.
func startRecording(option: VideoOption, url: URL, minFreeBytes: Int64, dropPolicy: DropPolicy) async throws(RecordingError)
// stopRecording() -> Bool keeps its meaning: true while a clip records or is being finished on either path.

// SessionConfiguration
var recorder: RecorderPath = .system          // decoded with decodeIfPresent; a saved start without it is .system
static func make(lens:mode:video:photo:access:needsFrames:recorder:) -> SessionConfiguration   // recorder defaults to .system

// SessionEvent
case framesDropped(clip: String, total: Int)  // clip is CaptureStore.clipKey; writer path only

// LookAvailability
static let needsSystemRecorder = "Looks are not shown with ProRes or Log."
static let turnedOffForRecorder = "Look turned off. Looks are not shown with ProRes or Log."
static func isOffered(mode: CaptureMode, colour: ColourMode, recorder: RecorderPath) -> Bool
static func chips(looks: [Look], isOffered: Bool, recorder: RecorderPath) -> [Chip]

// CameraModel
var recorderPath: RecorderPath { get }        // .system outside video mode, else recordResolver.recorder(for: record)
private(set) var droppedFrames: Int           // 0 at each start; follows .framesDropped for the clip being recorded only
var dropPolicy: DropPolicy                    // DropPolicy.keepRecording until Task 7 saves it

// FakeSessionConfigurator
private(set) var recordings: [(url: URL, option: VideoOption, dropPolicy: DropPolicy)]
```

Rules. `sessionConfiguration` carries `recorderPath`. A path switch always changes `video`, so `ViewfinderChange.pausesPicture` (`ViewfinderChange.swift:16-24`) already raises the blur and `enqueueConfigure` (`CameraModel.swift:678-723`) already returns the controls to automatic: the cost of a switch is one configure, the same as a codec change today. Looks are offered in video only on the system path with Rec. 709 or P3, so `needsFrames` is never true with the writer; `settleLook` shows `turnedOffForRecorder`. `SavedStart.configuration(for:…)` passes `configuration.recorder` to the look rule; the launch join already compares whole configurations (`CameraModel+Launch.swift:43`). `.framesDropped` is ignored unless `isRecording`, it is not a sweep clip and `clip` is `recordingClip`'s key. A result with `.stopped(.droppedFrames, …)` goes through `recordingDidFinish` untouched.

- [ ] **Step 1: Failing tests** (merged phone list, fake session). `aProResSelectionAsksForTheWriter` and `photoModeNeverAsksForTheWriter`. `switchingPathsIsOneConfigureBehindTheBlur` (HEVC to ProRes to HEVC: `fake.applied.map(\.recorder) == [.writer, .system]`, `pausesPicture` true each way, `manual == .automatic`). `theStartCarriesTheDropPolicy`. `aDropCountShowsOnlyForTheClipBeingRecorded` (another clip's key leaves 0; the current clip's sets 4; the next start reads 0; ignored when idle and during a sweep). `aClipStoppedForDropsSaysSoAndIsKept` (notice `droppedFramesStopNotice`, `lastCapture` set, `isRecording` false, a selection held during the clip configures). `aLookIsTurnedOffOnTheWriterPath` (look nil, notice `turnedOffForRecorder`, `needsFrames` false, chips dimmed with `needsSystemRecorder`). `theSweepNeverRecordsAWriterOption`. `SavedStartTests.aStartSavedBeforeRecorderPathsDecodesAsSystem` (JSON without the key) and `aWriterStartKeepsItsFramesRule`. `ViewfinderChangeTests.aRecorderSwitchPausesThePicture`.
- [ ] **Step 2: Run and see fail.** `scripts/test.sh CameraModelWriterTests`, exit 65.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** all of `scripts/test.sh`, then the device SDK compile.
- [ ] **Step 5: Commit.** `feat: carry the recorder path through the session protocol and the model`

### Task 6: The session's writer path

**Files:** Create `OpenCam/Capture/WriterClipPlan.swift`, `WriterOpening.swift`, `WriterSink.swift`, `WriterReport.swift`, `WriterRecorder.swift`, `ClipFinisher.swift`. Modify `MovieRecorder.swift:112-147` (moved into `ClipFinisher`, behaviour unchanged), `ClipSidecar.swift`, `RecordingError.swift`, `CameraSession.swift` (`:109`, `:164-168`, `:179`, `:505-520`, `:599-628`), `OpenCam/Capability/WriterSupport.swift`. Test: create `OpenCamTests/WriterClipPlanTests.swift`, `WriterSinkTests.swift`, `ClipFinisherTests.swift`; modify `WriterOptionsTests.shippedSupportIsOnlyWhatIsWired`.

**Interfaces. Consumes:** Tasks 4 and 5. **Produces:**

```swift
nonisolated struct WriterClipPlan: Sendable, Equatable {
    let url: URL; let codecType: String; let width: Int; let height: Int
    let averageBitRate: Int?          // HEVC tiers only, from DataRateEstimator
    let frameRate: Int; let rotationDegrees: Double
    let bakesLog: Bool; let policy: DropPolicy; let minFreeBytes: Int64
    static func make(option: VideoOption, url: URL, bufferWidth: Int, bufferHeight: Int, rotationDegrees: Double,
                     policy: DropPolicy, minFreeBytes: Int64) -> WriterClipPlan
}
nonisolated protocol WriterOpening { func open(_ plan: WriterClipPlan, recordsSound: Bool) throws(RecordingError) }
nonisolated struct WriterReport: Sendable { let end: WriterEnd; let facts: DropFacts; let hasFrames: Bool; let errorText: String? }

/// Owns the AVAssetWriter and WriterClipState. Every member is called inside writerQueue.sync.
nonisolated final class WriterSink: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate, WriterOpening {
    init(writerQueue: DispatchSerialQueue, onDrops: @escaping @Sendable (Int) -> Void, onFinished: @escaping @Sendable () -> Void)
    func receiveVideo(_ sampleBuffer: CMSampleBuffer, arrival: Duration)   // internal so tests deliver frames without a connection
    func receiveAudio(_ sampleBuffer: CMSampleBuffer)
    func receiveDrop(_ reason: DropReason, arrival: Duration)
    func storage(freeBytes: Int64)
    func end(_ end: WriterEnd) -> Bool          // true while a clip is in flight
    func takeReport() -> WriterReport?
}
/// Owns the two outputs, the three queues and the sink. Called on the session actor.
nonisolated final class WriterRecorder {
    let videoOutput: AVCaptureVideoDataOutput; let audioOutput: AVCaptureAudioDataOutput
    init(results: AsyncStream<RecordingResult>.Continuation, events: AsyncStream<SessionEvent>.Continuation, onFinished: @escaping @Sendable () -> Void)
    func preparePixelFormat(for colour: ColourMode) -> Bool      // x420 for HLG and Log, 420v for Rec. 709; false when not offered
    func start(option: VideoOption, url: URL, minFreeBytes: Int64, policy: DropPolicy, device: AVCaptureDevice, recordsSound: Bool) throws(RecordingError)
    func end(_ end: WriterEnd) -> Bool
    func collect()                                               // after onFinished: detach delegates, read the report, yield the result
    var isClipInFlight: Bool { get }
    func audioLevels() -> [Double]
}
nonisolated enum ClipFinisher {
    /// Reads the clip back, writes the sidecar, returns the result. `outcome` receives whether the file has a video track longer than zero.
    static func finish(_ recording: PendingRecording, recorder: RecorderPath, drops: DropFacts?, errorMessage: String?,
                       outcome: @Sendable (_ isReadable: Bool) -> RecordingOutcome) async -> RecordingResult
}
// ClipSidecar: `let recorder: RecorderPath?`, `let drops: DropFacts?` (optional, so older sidecars still decode: ClipDuration.swift:14).
// RecordingError: `.writerNotAttached`, `.writerNotOpened(codec: String, reason: String)`.
// WriterSupport.shipped(isSimulator: false) == [.proRes, .proResSDR]
```

**Design, settled here.**

- *Queues.* `opencam.session` (the actor): attach, start, end, collect. `opencam.record.video` and `opencam.record.audio`: the outputs' delegate queues (serial, `AVCaptureAudioDataOutput.h:55`). `opencam.record.writer`: the only queue that touches the writer, its inputs and `WriterClipState`. The video, audio and session queues enter it with `sync`; it never waits on any of them. Out of it go only `@Sendable` closures that start a `Task`.
- *Ownership.* The actor owns `WriterRecorder`, which owns the sink. Neither is `Sendable` (`@available(*, unavailable) extension WriterSink: Sendable {}`, as on the diagnostic branch). The delegate callbacks compute `arrival`, read the drop reason, and call `writerQueue.sync { receive… }`; the sample buffer never leaves the callback.
- *Outputs.* In `configureSession`: `attachMovieOutput(mode == .video && recorder == .system)`, then `attachWriterOutputs(mode == .video && recorder == .writer, recordsSound: includesAudio)`. The video output is full size (`automaticallyConfiguresOutputBufferDimensions = false`, `deliversPreviewSizedOutputBuffers = false`, `AVCaptureVideoDataOutput.h:252, :266`), keeps late frames (`alwaysDiscardsLateVideoFrames = false`, as measured), connection at angle 0 and unmirrored like `attachFrameOutput`. After `applyFormat` (`CameraSession.swift:179`), `preparePixelFormat`; false throws `.cannotAddOutput(name: "record frames")`, so the configure fails and the model restores the last selection with "That format could not be used." An audio output that cannot be added yields `.microphoneUnavailable`, as a microphone that cannot attach does today. `configure` also refuses while `writerRecorder.isClipInFlight` (`:109`).
- *Start.* `CameraSession.startRecording` routes on `lastWorkingConfiguration?.recorder`. Writer: session running, outputs attached (`.writerNotAttached`), no clip in flight (`.alreadyRecording`); `WriterClipPlan.make` with the active format's dimensions and `RotationCoordinator.videoRotationAngleForHorizonLevelCapture`; `writerQueue.sync { open }`; set both delegates; start a once-a-second task on the actor that reads `FreeSpace.availableBytes()` and passes it to `sink.storage`. The delegates are set only while a clip records.
- *Open* (deprecated calls contained here): `AVAssetWriter(outputURL:fileType: .mov)`, `movieFragmentInterval` 10 s; video settings ProRes `[codec, width, height]` as the check built them, HEVC from `recommendedVideoSettings(forVideoCodecType:assetWriterOutputFileType:)` only after the codec is found in `availableVideoCodecTypesForAssetWriter(writingTo: .mov)` (`AVCaptureVideoDataOutput.h:147`: asking otherwise raises an exception), with the tier's average bit rate; no `AVVideoColorPropertiesKey`, so the file is tagged from the frames (`AVVideoSettings.h:166`); video input real-time with `transform` set to the rotation (`AVAssetWriterInput.h:317`), so no buffer is rotated; audio input from `recommendedAudioSettingsForAssetWriter(writingTo: .mov)` (`AVCaptureAudioDataOutput.h:117`), else AAC 48 kHz stereo 128 kb/s as in check 2; every `canApply` and `canAdd` checked; any refusal is `.writerNotOpened`.
- *First frame, sync, last frame.* `WriterClipState.video` decides: `startSession(atSourceTime:)` at the first frame's own time, then append. Sound appends with its own time once video has started. On any end: both inputs `markAsFinished`, `endSession(atSourceTime: endTime)` while the writer is still writing, so sound past the last frame is edited out (`AVAssetWriter.h:215-239`), then `finishWriting`. All appends have returned by then because they share the queue (`AVAssetWriter.h:271`).
- *Ends.* User: `end(.user)`. Drops under "Stop recording": the state returns `.finish` inside the drop callback. Storage: the watch task. Interruption and backgrounding: the `wasInterruptedNotification` observer starts `Task { await owner?.endWriterClip(.interrupted) }`. Stopped camera: the runtime-error observer does the same with `.cameraStopped`. Failed append: `videoWritten(false)`; `finishWriting` then reports the failure and the fragments keep what was written. All arrive at one place: the writer's completion handler calls `onFinished`, the actor runs `collect()`, which clears the delegates, cancels the watch, reads the report through the writer queue and yields `ClipFinisher.finish(…)` into the same `recordingContinuation` the movie recorder uses. The model's `followRecordings` does not change.
- *Never a hang, never a lost file.* Ten seconds after any end without a completion, `collect()` runs with `.timedOut`: the file stays, the result is `.stopped(.noResult, isPlayable: false)` ("Recording stopped. The clip may be incomplete."), and a late completion is ignored. `cancelWriting()` runs only for a clip with no frame, whose result is `.failed`. A missing file after a finish is `.failed`, as `MovieRecorder` reports it today.
- *Meters.* `audioLevels()` reads the audio data output's connection when the movie output is not attached.

- [ ] **Step 1: Failing tests.** `WriterClipPlanTests`: `aProResPlanHasNoBitRate`, `anHEVCLogPlanCarriesItsTierAndBakes`, `rotationAndSizeComeFromTheCaller`. `WriterSinkTests` (synthetic 320 x 180 `420v` sample buffers at k/30 s, a temporary folder; ProRes 422 Proxy, or H.264 if the Simulator's writer refuses ProRes, stated in the task report): `thirtyFramesBecomeAOneSecondClip` (read back by `ClipInspector`: 30 frames, about 1 s); `anInterruptedClipIsStillAPlayableFile` (`end(.interrupted)` after 15 frames: readable, report end `.interrupted`); `aStopWithNoFrameLeavesNoFileAndReportsNoFrames`; `stopRecordingPolicyFinishesTheFileAtTheFirstDrop` (`receiveDrop(.late)` after 10 frames: `onFinished` runs once, report `stoppedRecording`, file readable); `dropsReachOnDrops` (count 1 delivered); `twoEndsFinishOnce`. `ClipFinisherTests`: `aMissingFileIsFailed`; `theSidecarCarriesTheRecorderAndTheDrops`; `aSidecarWrittenBeforeTheseFieldsStillDecodes`.
- [ ] **Step 2: Run and see fail.** `scripts/test.sh WriterSinkTests`, exit 65.
- [ ] **Step 3: Implement.** Copy the containment pattern from `RecorderCheck2Sink` (deprecated members, the adaptor stored as `AnyObject?` behind a deprecated accessor, added in Task 9). Typed errors thrown inside `sync` are caught and rethrown as `RecordingError` by the caller.
- [ ] **Step 4: Run** all of `scripts/test.sh`; device SDK compile in Debug and Release, 0 warnings.
- [ ] **Step 5: Commit.** `feat: record ProRes through an asset writer beside the movie output`

### Task 7: The dropped-frame count, the setting and background finishing

**Files:** Create `OpenCam/UI/DroppedFramesBadge.swift`, `OpenCam/UI/DropChoice.swift`, `OpenCam/App/CameraModel+Drops.swift`, `OpenCam/App/BackgroundWork.swift`, `OpenCam/App/SystemBackgroundWork.swift`. Modify `OpenCam/Capture/DropPolicy.swift`, `OpenCam/UI/FoldedVerticalVideoView.swift:12-35`, `FoldedHorizontalView.swift:16-18`, `VideoRecordRows.swift:26-31`, `RecordSettingsSheet.swift`, `CameraRootView.swift`, `OpenCam/App/LaunchConfig.swift`, `CameraModel.swift` (init), `CameraModel+Recording.swift:124-126`. Test: create `OpenCamTests/DropSettingTests.swift`, `FakeBackgroundWork.swift`; modify `LaunchConfigTests`, `CameraModelWriterTests`, `MainThreadCostTests`.

**Interfaces. Consumes:** Tasks 5 and 6. **Produces:**

```swift
extension DropPolicy {
    static let rowTitle = "When frames drop"
    var title: String                                   // "Keep recording", "Stop recording"
    static func line(_ policy: DropPolicy, recorder: RecorderPath) -> String
    static func load(from defaults: UserDefaults) -> DropPolicy   // key "dropPolicy", .keepRecording when absent
    func save(to defaults: UserDefaults)
}
struct DropChoice { let chips: [Chip]; let selectedID: String; let reason: String; let onSelect: (String) -> Void }
struct DroppedFramesBadge: View { let model: CameraModel; var isCompact = false }
@MainActor protocol BackgroundWork: AnyObject { func end() }
// CameraModel: `var dropChoice: DropChoice`, `func appEnteredBackground()`,
//   `var beginBackgroundWork: @MainActor (String) -> any BackgroundWork` (SystemBackgroundWork wraps beginBackgroundTask and endBackgroundTask)
// LaunchConfig: `var droppedFrames = 0`   // -droppedFrames <n>, with -recording on (honoured in the Simulator only; scripted)
```

Strings. `line`: writer and keep, "Dropped frames are counted on screen and saved with the clip."; writer and stop, "Recording stops at the first dropped frame. The clip is saved."; system, either policy, "This format is checked for dropped frames when the clip ends. It does not stop early." Badge: caption "DROPPED", the count as its value in the alert colour; VoiceOver label "Dropped frames", value the count.

Layout. `CameraLayout.swift:20-26` uses the same views on the folded and the open display, so two placements cover every layout that records. The badge is `ReadoutView` (caption, value, `isAlert`), `fixedSize`, on a glass capsule, drawn only while `isRecording && droppedFrames > 0`, always as an overlay, so no control moves. Portrait video: `.overlay(alignment: .topTrailing)` on the `ZStack`, top padding `insets.top + Theme.Space.l + Theme.Size.minTarget + Theme.Space.s` (the inset the stand-in caption uses, `FoldedVerticalVideoView.swift:13`), trailing `Theme.Space.l`, compact. Landscape: `.overlay(alignment: .topTrailing)` on the `ViewfinderArea`, padding `Theme.Space.s`. The histogram slot (`BottomBar.swift:32-35`) stays empty. The badge reads `droppedFrames` in its own body, so a new count re-runs only it. The setting is a `ChipRow` (2 columns) after the Look row and before the footer, in video only.

Rules. The policy is saved outside `SavedSelections`, so `SavedStart` is unaffected; a scripted launch neither loads nor saves it. `recordingDidFinish` takes the count for the notice from `sidecar.drops?.total`, else `sidecar.actual?.droppedFrames`. `appEnteredBackground()` (from `scenePhase == .background` in `CameraRootView`): while a writer clip records, begin one background work item; end it when that clip's result arrives or on expiry. It never stops the clip itself: the session's interruption does, with `.interrupted`. In the Simulator `-recording on -droppedFrames 3` sets `droppedFrames` at init, beside the existing simulated recording (`LaunchConfig.swift:42-45`, `CameraModel.swift:210-211`).

- [ ] **Step 1: Failing tests.** `DropSettingTests`: `theThreeLines`, `theTwoChips`, `thePolicyIsSavedAndRestored`, `aScriptedLaunchNeitherLoadsNorSavesIt`, `noStringHasAnEmDash`. `LaunchConfigTests`: `-droppedFrames 3` parses and is scripted; a Simulator model with `-recording on -droppedFrames 3` reads 3, without `-recording on` reads 0. `CameraModelWriterTests`: `theNoticeUsesTheWritersCount` ("OC_0007 dropped 3 frames." from `drops.total` with no file count); `backgroundingDuringAWriterClipHoldsBackgroundWorkUntilTheResult` (begun once, ended at the result; not begun on the system path or when idle). `MainThreadCostTests`: the badge's read in `bodyReads`.
- [ ] **Step 2: Run and see fail.** `scripts/test.sh DropSettingTests`, exit 65.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** all of `scripts/test.sh`; device SDK compile.
- [ ] **Step 5: Tap test and screenshots.** `-mode video -recording on -droppedFrames 3` in portrait and landscape: the badge sits under the readout bar's trailing end (portrait) and in the picture's top trailing corner (landscape), clear of the "No camera in Simulator" caption. `-recording on` alone: no badge, and every control where `docs/screenshots/qa` has it. `-screen record -formats phone -cameraLook none`: the row, then tap "Stop recording", then tap ProRes: the line changes each time. `recorder-count-{portrait,landscape}.png`, `recorder-count-none-portrait.png`, `recorder-drops-{portrait,landscape}-{keep,stop,prores}.png`.
- [ ] **Step 6: Commit.** `feat: count dropped frames on screen and let a drop stop the recording`

### Task 8: The Log curve and its two tables

**Files:** Create `OpenCam/Render/HLGCurve.swift`, `OpenCam/Render/LogProfile.swift`. Modify `OpenCam/Render/LookCompiler.swift:14` (a per-channel builder over the existing `build`), `OpenCam/Render/LookRenderer.swift:83-91`. Test: create `OpenCamTests/LogProfileTests.swift`, `LookRendererTableTests.swift`.

**Interfaces. Produces:**

```swift
/// ITU-R BT.2100 HLG. a = 0.17883277, b = 1 - 4a, c = 0.5 - a ln(4a).
nonisolated enum HLGCurve {
    static func sceneLight(signal: Double) -> Double   // s <= 0.5: s*s/3; else (exp((s - c)/a) + b)/12
    static func signal(sceneLight: Double) -> Double   // E <= 1/12: sqrt(3E); else a ln(12E - b) + c, continued above E = 1
}
/// The baked profile: a log encoding of the scene light the HLG signal stands for, per channel on BT.2020 R'G'B'.
nonisolated enum LogProfile {
    static let greySignal = 0.38     // an 18 percent grey card in HLG (ITU-R BT.2408)
    static let greyCode = 0.45
    static let slope = 0.09          // code values per stop where the curve is logarithmic
    static let offset = 0.01
    static let blackCode: Double     // 0.067687
    static let peakCode: Double      // 0.837240
    static func encode(signal: Double) -> Double       // HLG signal 0...1 to Log code
    static func decode(code: Double) -> Double         // Log code to HLG signal; 0 at and below blackCode; not clamped above peakCode
    static func bakeCube() -> ColourCube               // 33 points, encode on each channel
    static func previewCube() -> ColourCube            // 33 points, decode on each channel
}
// LookCompiler: static func cube(dimension: Int = ColourCube.standardDimension, perChannel: (Float) -> Float) -> ColourCube
// LookRenderer: let hlg: CGColorSpace   // CGColorSpace.itur_2100_HLG
//               func applyTable(_ image: CIImage, cube: ColourCube, in colourSpace: CGColorSpace) -> CIImage
//               applyCube(_:cube:) becomes applyTable(…, in: displayP3); its results do not change.
```

Maths. Let E = `sceneLight(signal:)`, g = 0.38² / 3 = 0.0481333 (mid-grey's scene light), x = 0.18 E / g. `encode` = A log2(x + B) + C with A = 0.09, B = 0.01, C = 0.45 - A log2(0.19) = 0.6656336. `decode`: x = 2^((L - C) / A) - B, E = max(x, 0) g / 0.18, then `signal(sceneLight:)`. Black is lifted, grey sits at 0.45, the whole HLG range fits under 0.84, and the slope at grey is 0.0853 per stop (about 75 ten-bit codes).

| HLG signal | 0 | 0.10 | 0.20 | 0.38 | 0.50 | 0.75 | 0.90 | 1.00 |
|---|---|---|---|---|---|---|---|---|
| Log code | 0.067687 | 0.172780 | 0.300033 | 0.450000 | 0.518348 | 0.665745 | 0.767171 | 0.837240 |

Tolerances (computed for this plan): the formulas round-trip within 1e-6; the 33-point bake table is within 0.004 of `encode` everywhere (worst near signal 0.015); bake then preview through the two tables returns the signal within 0.008 below 0.05 and within 0.001 from 0.05 up. `decode` is left unclamped above the peak so the preview table has no corner at 0.837.

- [ ] **Step 1: Failing tests.** `LogProfileTests`: `referenceValues` (the eight above within 1e-5; `encode(greySignal) == greyCode`); `encodeIsMonotonic` (1,001 steps); `theFormulasRoundTrip` (1e-6 over 0...1); `theBakeTableFollowsTheCurve` (linear interpolation of the 33 nodes within 0.004); `bakeThenPreviewReturnsThePicture` (0.008 below 0.05, 0.001 above); `hlgCurveMatchesBT2100` (0.5 gives 1/12; 0.75 gives 0.264963; 1 gives 1; inverse within 1e-9). `LookRendererTableTests` (a constant-colour `CIImage` in HLG, rendered to an RGBAf bitmap in HLG through `LookRenderer.shared.context`): `aTableInHLGMapsGreyToTheCurveValue` (0.38 gives 0.45 within 0.005); `aTableInHLGKeepsPeakWhite` (1.0 gives 0.837 within 0.005); `previewAfterBakeReturnsThePicture` (0.2, 0.38, 0.75 within 0.01); `applyCubeIsUnchanged` (an existing look's output equal before and after the refactor).
- [ ] **Step 2: Run and see fail.** `scripts/test.sh LogProfileTests`, exit 65.
- [ ] **Step 3: Implement.** Foundation for the maths; the two cubes through `LookCompiler`.
- [ ] **Step 4: Run** the suites, then all of `scripts/test.sh`.
- [ ] **Step 5: Commit.** `feat: define the Log curve and compile its bake and preview tables`

### Task 9: The baked Log render

**Files:** Create `OpenCam/Capture/RecordingRender.swift`. Modify `OpenCam/Capture/WriterSink.swift`, `WriterRecorder.swift`, `OpenCam/Capability/WriterSupport.swift`. Test: create `OpenCamTests/RecordingRenderTests.swift`; modify `WriterSinkTests`, `WriterOptionsTests.shippedSupportIsOnlyWhatIsWired`.

**Interfaces. Consumes:** Tasks 6 and 8. **Produces:**

```swift
/// Draws one frame through a table into a pooled buffer of the frame's own format. Used on the video queue only.
nonisolated final class RecordingRender {
    init(cube: ColourCube, renderer: LookRenderer = .shared)
    func render(_ source: CVPixelBuffer) -> CVPixelBuffer?   // nil when the pool or the render failed
}
// WriterSink: `func admitVideo(pts: CMTime, duration: CMTime, arrival: Duration) -> Bool` and
//   `func receiveRendered(_ buffer: CVPixelBuffer?, pts: CMTime, duration: CMTime)`; open() adds the pixel buffer adaptor when plan.bakesLog.
// WriterSupport.shipped(isSimulator: false) == .all
```

Rules. With `bakesLog` the video callback runs three steps: `writerQueue.sync { admitVideo }` (counts the frame, starts the session, and refuses a frame the writer is not ready for or that is more than one frame behind), then the render on the video queue with the writer queue free for sound, then `writerQueue.sync { receiveRendered }`, which appends through the adaptor or counts `renderFailed`. The callback is synchronous and a late frame is refused before it is rendered, so a backlog cannot build: at most the frame being worked on is held. The render is `renderer.applyTable(CIImage(cvPixelBuffer:), cube: LogProfile.bakeCube(), in: renderer.hlg)` into `CIRenderDestination(pixelBuffer:)` with `colorSpace = renderer.hlg`, started on `renderer.context` and waited to completion, as check 2 times it. HLG is only the carrier on both sides, so the values written are the table's output. The pool matches the source (size, `x420`, IOSurface, Metal), minimum 3, allocation threshold 6. Before the render the destination gets the BT.2020 matrix; after it, BT.2020 primaries and the Rec. 709 transfer function, so the file is not presented as HDR and reads as `.log` (Task 2).

- [ ] **Step 1: Failing tests** (a 64 x 64 `x420` buffer filled with one grey, tagged HLG BT.2020; ten-bit values sit in the high bits of each 16-bit sample). `aGreyFrameComesOutAtTheCurveValue` (Y 397 in, 458 out, within 3). `blackIsLiftedAndPeakWhiteIsKept` (64 gives 123; 940 gives 797; within 3). `neutralStaysNeutral` (Cb and Cr within 3 of 512). `theOutputIsTaggedBT2020WithTheRec709Curve`. `theSourceIsNotChanged`. `aHeldPoolReturnsNil` (six results kept: the seventh is nil). `WriterSinkTests.aLateFrameIsRefusedBeforeItIsRendered` (`admitVideo` false, `behind` counted) and `aFailedRenderIsADrop`.
- [ ] **Step 2: Run and see fail.** `scripts/test.sh RecordingRenderTests`, exit 65. If the Simulator cannot render into `x420`, say so in the task report, keep the tests that do not need the destination format, and leave the pixel checks to the device checklist.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** all of `scripts/test.sh`; device SDK compile in Debug and Release, 0 warnings.
- [ ] **Step 5: Commit.** `feat: bake the Log curve into frames on their way to the writer`

### Task 10: The device checklist

**Files:** Modify `docs/device-checklist.md` (new section "10. The recorder", before "Things to decide after holding it"). Re-read every PNG in `docs/screenshots/recorder/`.

- [ ] **Step 1: Write the section,** in this order:
  - Before anything else: build `diag/recorder-check` in Release, grant the microphone, launch with `-recorderCheck2` pointed at a busy, moving scene, pull `Documents/recorder-check-2.json` into `docs/research`. Read it with "To confirm on the phone" below.
  - ProRes 422 HQ 4K 30 HLG for 60 s on 1x: `OC_000n.MOV` plays in Files and in the editor used; sidecar `recorder: writer`, `apch`, 3840 x 2160, about 30 fps, `hasAudio` true, `drops.total` 0, `megabitsPerSecond` beside the chip's figure. Repeat Proxy, LT, 422.
  - ProRes 422 HQ 4K 30 Rec. 709 (8-bit frames): records, plays, tagged Rec. 709. If it fails, note the journal line.
  - ProRes 422 HQ 4K 60 HLG for 60 s: note `drops`, heat, the count on screen.
  - Log with ProRes and with HEVC at 4K 30, then 4K 60: the viewfinder shows the normal picture; the clip is flat; a grey card reads near 45 percent; the sidecar colour is Log; no HDR badge in Photos or Files.
  - A clip in each of the four orientations and on each camera is upright; sound stays in sync over 5 minutes (clap at start and end).
  - HEVC to ProRes and back: one blur each way, the controls return to automatic, HEVC clips are as before (`recorder: system`).
  - Launch with ProRes saved: the launch line shows the saved start adopted.
  - During a writer clip: lock the phone; take a call; fill storage with `-freeSpaceMarginMB`; cover the lens and force heat. Each time the clip is saved, plays whole, and the notice is the right one.
  - "Stop recording": provoke a drop (4K 60 Log while the phone is hot): the clip stops, is saved, the notice reads "Recording stopped. A frame was dropped. Clip saved."
  - The count on the open display, portrait and landscape, with a slider open: it covers no readout, the format button, the shutter or the slider column.
  - Meters move on the writer path; the record haptics are felt.
  - Idle with ProRes selected for 5 minutes: note the heat against HEVC.
- [ ] **Step 2: Commit.** `docs: add the recorder's device checks`

## Not in this plan

RAW video, 4444, ProRes RAW, external recording, stabilisation modes, timecode tracks, proxies, lens switching while recording, audio source choice, headphone monitoring, monitoring overlays (decision 8). Also: a look baked into video, and looks in the viewfinder on the writer path (Read first 5); the preview table drawn in the viewfinder or applied to Log clips in the Library (Read first 3); ProRes or Log above 60 fps; H.264 in Log (8-bit); P3 with ProRes; writer options in the format sweep; Pro Video Storage (`AVAssetWriter.usesProVideoStorage`, new in iOS 27); the new receiver-based writer API; a live count on the system path.

## To confirm on the phone

What check 2's numbers decide (each is a change to `WriterOptions.isOffered`, with a test, unless stated):

- Trials 1 to 3 (plain ProRes with preview and sound): `framesNotAppendedInputNotReady + framesDroppedByOutput` of 0 changes nothing. More than 1 percent of `framesDelivered` in trial 3 only: 422 HQ at 4K is offered up to 30 fps. In trial 1 or 2: stop and bring the numbers to the controller before Task 6's switch ships.
- `dataRateMegabitsPerSecond` in trials 1 to 3 against 884, 1178 and 1768: above the table by more than 5 percent, the estimates take the measured figure for that cell; at or under it, the table stays, so the time shown is never too long.
- Trials 4 to 6 (table pass): `render.p95Milliseconds` plus `video.appendMeanMilliseconds` under the frame time (33.3 or 16.7 ms) and `framesDroppedRenderBusy` under 1 percent keeps Log at that size and rate. Otherwise Log at 4K is offered up to 30 fps (trial 6 fails) or at 1080p only (trial 5 fails), and the unmanaged render in the open questions is tried.
- `audio.settingsSource` is "recommended" and `audio.buffersNotAppendedInputNotReady` is 0; `wasPreviewingAtEnd` is true; `thermalAfter` is below serious; the table trials' `file` read-back shows the adaptor worked with ProRes and `x420`.

Not covered by either check, so first on the checklist: ProRes from 8-bit `420v` frames; sizes other than 1080p and 4K, rates other than 30 and 60, and the other four lenses; the writer's HEVC with a tier's bit rate; the track transform on the front cameras; a 10 s fragment interval's effect on the finished file and on editors; the BT.2020 with Rec. 709 tagging of Log in Photos, Files and the editor; that a background task plus the interruption finishes a clip before the writer fails; the time a path switch takes; heat while idle with the full-size output attached; memory when the writer stalls with late frames kept.

## Rulings on the open questions (controller, 2026-11-12, overnight run)

1. **Estimates:** adopt Apple's table as Task 1 has it. The controller's earlier "707" was Apple's 24p row; the app's 881 at 4K 30 was already right.
2. **The preview table:** not run in the viewfinder; built and tested for viewing Log clips later.
3. **ProRes in Rec. 709 (8-bit frames):** shipped on behind its own switch, first on the phone's checklist, removed from `shipped` if it fails there.
4. **Sizes:** every 10-bit size up to 60 fps, guarded; narrowed to 1080p and 4K if the phone shows trouble.
5. **Log's file tags:** BT.2020 primaries with the Rec. 709 transfer function.
6. **The render's colour handling:** the colour-managed pass, unless check 2's trials 5 and 6 are too slow.
7. **The deprecated writer calls:** kept, contained as the diagnostic contains them.
8. **Fragment interval:** 10 seconds.

The owner is asleep for this build. Naming ("Log" with the detail "baked curve"; "Apple Log" listed as unavailable with its reason) and the "Keep recording" default are the controller's calls for him to confirm.
