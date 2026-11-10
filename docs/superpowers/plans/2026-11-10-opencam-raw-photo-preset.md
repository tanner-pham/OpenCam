# OpenCam RAW Photos on the Duo: Photo Preset Fix

> **For agentic workers:** one task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On the iPhone Duo, photo mode offers RAW and RAW + HEIF on the back wide and ultra wide lenses and can capture them.

**Why:** Measured on the phone on 2026-11-10 (iPhone19,4, iOS 27.2 build 24B91020) with a diagnostic on branch `diag/raw-check`:

| Session setup | Back wide | Back ultra wide |
|---|---|---|
| `sessionPreset = .photo`, photo output only | Bayer RAW `bgg4`, DNG | Bayer RAW `rgg4`, DNG |
| `.photo` plus a video data output | RAW offered | RAW offered |
| `.inputPriority`, the same 4032 x 3024 `420f` format picked by hand | no RAW | no RAW |

The readings were the same on a stopped and on a running session. Under the preset the active format is 4032 x 3024 `420f` and photo sizes go up to 8064 x 6048. The front cameras offer no RAW. Apple ProRAW is not supported. OpenCam uses input priority everywhere, so its scan on the phone lists HEIF only and it cannot shoot RAW.

**Spec:** `docs/superpowers/specs/2026-11-09-duo-camera-design.md` (RAW photo capture). Camera core plan: `docs/superpowers/plans/2026-11-09-duocam-camera-core.md`, whose Global Constraints apply unchanged (Swift 6, no third-party dependencies, no force unwraps or `try!`, one type per file, errors as `[Module:Function] Description — {context}`, no new `@unchecked Sendable`, no `nonisolated(unsafe)`, no `@preconcurrency import`, conventional commits, no attribution lines). API facts come only from `docs/research/capture-apis.md` or a grep of the SDK headers, never from memory.

## Global Constraints

- Branch `fix/raw-photo-preset`, stacked on `feat/looks-in-camera`.
- Video mode is untouched: it keeps `.inputPriority`, its format choice, its colour space and its outputs exactly as today. Every change below is reached only in photo mode or in the scan's photo reading.
- With a look selected, photo mode still attaches the frame output; the measurement shows a data output does not remove RAW.
- Nothing here can be run in the Simulator beyond unit tests of the pure parts. It is verified by those tests, the device SDK compile, a review, and then on the phone.

## Review Focus

1. The scan must not report RAW for a lens whose preset reading has none (the front cameras). Pinned by `PhotoPresetReadingTests.frontLensWithoutRAWGetsHEIFOnly`.
2. A cached scan made before this fix must not be reused. Pinned by `CapabilityCacheTests.scanFromBeforeThePhotoPresetIsNotReused`.
3. Only the preset's photo sizes are offered, so the tiny sizes of small video formats disappear from the photo list. Pinned by `PhotoPresetReadingTests.onlyThePresetsSizesAreOffered`.
4. A lens whose camera cannot take the photo preset keeps today's photo options and today's input-priority configuration. Pinned by `PhotoPresetReadingTests.noPresetReadingKeepsTheFormatsOwnPhotoFields`.
5. The photo size must be applied only once the preset's format is the active format. Not unit-testable; the reviewer checks the order in `CameraSession`.

---

### Task 1: Photo mode on the photo preset

**Files:**
- Create: `OpenCam/Capability/PhotoPresetReading.swift`
- Modify: `OpenCam/Capture/CapabilityScanner.swift`, `OpenCam/Capture/CameraSession.swift`, `OpenCam/Capability/CaptureCapabilities.swift`, `OpenCam/Capability/CapabilityCache.swift`, and `docs/device-checklist.md` (section 3 and the "First launch" lens line say what the phone really offers)
- Test: `OpenCamTests/PhotoPresetReadingTests.swift`; Modify the existing capability cache tests

**Interfaces:**
- Consumes: `FormatDescriptor` (`lensID`, `width`, `height`, `maxPhotoDimensions: [PhotoSize]`, `hasBayerRAW`), `PhotoSize`, `CapabilityMapper.photoOptions(from:lenses:)` (unchanged), `CaptureCapabilities`, `CapabilityCache.load(osBuild:modelIdentifier:)`, `SessionConfiguration` (`mode`, `lens`, `photo`), `CameraSession.apply`, `applyFormat`, `applyPhoto`, `applyPhotoDimensions`.
- Produces:

```swift
/// What one camera offers under the photo preset.
nonisolated struct PhotoPresetReading: Sendable, Equatable {
    var width: Int                 // the preset's active format
    var height: Int
    var sizes: [PhotoSize]         // that format's supportedMaxPhotoDimensions
    var hasBayerRAW: Bool
    /// The descriptors of one lens with their photo fields replaced by the reading: every descriptor loses its photo
    /// sizes and RAW flag, except one carrier (the first whose dimensions equal the reading's, else the first), which
    /// takes the reading's sizes and RAW flag. With a nil reading, or no descriptors, they come back unchanged.
    static func assign(_ reading: PhotoPresetReading?, to descriptors: [FormatDescriptor]) -> [FormatDescriptor]
}
// CaptureCapabilities.currentScanVersion = 2; var scanVersion: Int (a file without the key decodes as 1; the memberwise
//   initialiser defaults it to currentScanVersion so existing call sites compile).
// CapabilityCache.load returns nil unless scanVersion == CaptureCapabilities.currentScanVersion.
```

- [ ] **Step 1: Write the failing tests**

```swift
// OpenCamTests/PhotoPresetReadingTests.swift
@Suite struct PhotoPresetReadingTests {
    func descriptor(_ width: Int, _ height: Int, sizes: [PhotoSize], raw: Bool = false) -> FormatDescriptor {
        FormatDescriptor(lensID: "wide", width: width, height: height, isBinned: false, frameRateRanges: [1...60],
                         codecTypesByColourSpace: [0: ["hvc1"]], allowsCompressionProperties: true,
                         maxPhotoDimensions: sizes, hasBayerRAW: raw)
    }
    let tiny = PhotoSize(width: 192, height: 144), twelve = PhotoSize(width: 4032, height: 3024), fortyEight = PhotoSize(width: 8064, height: 6048)

    @Test func onlyThePresetsSizesAreOffered() {   // Review Focus 3
        let reading = PhotoPresetReading(width: 4032, height: 3024, sizes: [twelve, fortyEight], hasBayerRAW: true)
        let out = PhotoPresetReading.assign(reading, to: [descriptor(192, 144, sizes: [tiny, twelve]), descriptor(4032, 3024, sizes: [twelve]),
                                                          descriptor(3840, 2160, sizes: [twelve])])
        #expect(out.map(\.maxPhotoDimensions) == [[], [twelve, fortyEight], []])
        #expect(out.map(\.hasBayerRAW) == [false, true, false])
        #expect(out.map(\.width) == [192, 4032, 3840])          // nothing else about a descriptor changes
    }
    @Test func frontLensWithoutRAWGetsHEIFOnly() {   // Review Focus 1
        let reading = PhotoPresetReading(width: 2016, height: 1512, sizes: [twelve], hasBayerRAW: false)
        let out = PhotoPresetReading.assign(reading, to: [descriptor(2016, 1512, sizes: [twelve], raw: true)])
        #expect(out.map(\.hasBayerRAW) == [false]); #expect(out[0].maxPhotoDimensions == [twelve])
    }
    @Test func aReadingWithNoMatchingFormatUsesTheFirstDescriptor() {
        let reading = PhotoPresetReading(width: 4224, height: 2376, sizes: [fortyEight], hasBayerRAW: true)
        let out = PhotoPresetReading.assign(reading, to: [descriptor(1920, 1080, sizes: [twelve]), descriptor(3840, 2160, sizes: [twelve])])
        #expect(out.map(\.maxPhotoDimensions) == [[fortyEight], []]); #expect(out.map(\.hasBayerRAW) == [true, false])
    }
    @Test func noPresetReadingKeepsTheFormatsOwnPhotoFields() {   // Review Focus 4
        let before = [descriptor(192, 144, sizes: [tiny]), descriptor(4032, 3024, sizes: [twelve], raw: true)]
        #expect(PhotoPresetReading.assign(nil, to: before) == before)
        #expect(PhotoPresetReading.assign(PhotoPresetReading(width: 1, height: 1, sizes: [], hasBayerRAW: false), to: []).isEmpty)
    }
    @Test func theMapperOffersRAWOnlyOnTheUnzoomedLens() {
        // Through the existing mapper: RAW and RAW + HEIF at both sizes on the 1x lens, HEIF only on its 2x crop.
        let reading = PhotoPresetReading(width: 4032, height: 3024, sizes: [twelve, fortyEight], hasBayerRAW: true)
        let formats = PhotoPresetReading.assign(reading, to: [descriptor(4032, 3024, sizes: [twelve])])
        let wide = Lens(id: "wide", kind: .wide, label: "1x", deviceUniqueID: "d", zoomFactor: 1)
        let crop = Lens(id: "wide@2", kind: .wide, label: "2x", deviceUniqueID: "d", zoomFactor: 2)
        let options = CapabilityMapper.photoOptions(from: formats, lenses: [wide, crop])
        #expect(Set(options.filter { $0.lensID == "wide" }.map(\.format)) == Set(PhotoFormat.allCases))
        #expect(Set(options.filter { $0.lensID == "wide@2" }.map(\.format)) == [.heif])
        #expect(Set(options.map { $0.width * $0.height }) == [4032 * 3024, 8064 * 6048])
    }
}

// Added to the capability cache tests (use that suite's existing way of making a cache and capabilities)
@Test func scanFromBeforeThePhotoPresetIsNotReused() throws {   // Review Focus 2
    // 1. Save capabilities, rewrite the file without the "scanVersion" key, load: nil.
    // 2. Save capabilities with the current version, load with the same build and model: equal to what was saved.
}
```

Use the real initialisers of `FormatDescriptor` and `Lens` as they are in the tree; if a label above differs from the code, keep the code's and keep every assertion.

- [ ] **Step 2: Run to see them fail** — `scripts/test.sh PhotoPresetReadingTests`. Expected: `cannot find 'PhotoPresetReading' in scope`.
- [ ] **Step 3: Implement.**
  - `PhotoPresetReading.assign` and the scan version, to the Interfaces.
  - `CapabilityScanner`: for each scanned lens, before its format walk, one more throwaway session holding ONLY the camera input and a photo output (the setup that was measured), `sessionPreset = .photo` when `canSetSessionPreset(.photo)`, committed; then read the device's active format dimensions, its `supportedMaxPhotoDimensions`, and whether `availableRawPhotoPixelFormatTypes` holds a Bayer RAW format; then remove the input and output. No `startRunning`. A lens where the preset cannot be set, or the session cannot take the camera, has no reading (nil) and is logged. The lens's descriptors pass through `PhotoPresetReading.assign`. The existing photo-plus-movie session and its format walk are unchanged.
  - `CameraSession.apply`: in photo mode the session preset is `.photo` when `canSetSessionPreset(.photo)`, else today's input-priority path, unchanged. Under the preset the app does not choose a format or a colour space by hand (the preset does; if the session's `automaticallyConfiguresCaptureDeviceForWideColor` is turned off anywhere, it is on in photo mode and as today in video mode). The lens's zoom is still applied. `maxPhotoDimensions` is set only after the configuration that selected the preset has been committed, when the preset's format is the device's active format; a size the active format does not list is `.noMatchingFormat` as today. Returning to video mode sets `.inputPriority` and applies the video format exactly as today. The restore of the last working configuration and the media-services recovery go through the same code.
  - `docs/device-checklist.md`: RAW is expected on 0.5x and 1x only; the front lenses are HEIF only; the lens line names the lenses the phone has.
- [ ] **Step 4: Run to see them pass** — `scripts/test.sh PhotoPresetReadingTests`, the capability cache suite, then the full `scripts/test.sh` (320 passing before this task; none removed or weakened), then the device SDK compile: `xcodebuild -project OpenCam.xcodeproj -scheme OpenCam -sdk iphoneos -destination generic/platform=iOS -derivedDataPath .build CODE_SIGNING_ALLOWED=NO build`. Expected: `** BUILD SUCCEEDED **`, 0 warnings.
- [ ] **Step 5: Commit**

```bash
git add OpenCam OpenCamTests docs/device-checklist.md
git commit -m "fix: use the photo preset in photo mode so RAW is offered on the Duo"
```

**On the phone** (controller and owner):
- [ ] After install the app scans again (the old cache is discarded) and `capabilities.json` lists RAW and RAW + HEIF for 0.5x and 1x, HEIF only for 2x and the front lenses, with only the preset's sizes.
- [ ] RAW + HEIF on 1x writes `OC_000n.DNG` and `OC_000n.HEIC`; the DNG's pixel size is noted.
- [ ] Photo mode's preview, the 2x lens, a look in the viewfinder, and switching to video and back all still work.
