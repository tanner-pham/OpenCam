# DuoCam design (working title)

Status: approved by Tanner on 2026-11-09. Built so far: a throwaway UI prototype and the P0 probe (compiled, never run).
Date: 2026-11-09

## Intent

A personal camera app for the iPhone Duo that makes the folded phone feel like a compact camera. The outer display is nearly all viewfinder, the system side strip holds the controls, and Camera Control is the shutter and the adjustment dial. It records formats Apple's Camera app withholds on the Duo (RAW photos, RAW video, Apple Log 2) and lists every codec, resolution and frame rate the device reports so the owner can test each one. It is sideloaded with a development certificate and never goes to the App Store or TestFlight.

## What Tanner decided

- Personal use only, pushed to his own Duo with his developer license.
- Native SwiftUI elements for the Liquid Glass look. No hand-drawn glass.
- Controls live on the Duo's control strip so the small outer display keeps more room for the viewfinder, and holding it feels like a small camera.
- Video is shot folded and horizontal. The strip is then on the left and its controls sit at the bottom of it. Held vertically, the strip is at the top right.
- Codec and resolution choice works like Blackmagic's Pocket Cinema Camera record settings. Every option is included so he can test them.
- Required capabilities: RAW photos, high quality video, RAW video, Apple Log 2, an Apple Log 2 preview LUT in the viewfinder, audio source choice with headphone monitoring, Lightroom-level colour control and masking for the RAW photos, Apple Pencil for correction and touch-ups, on-device subject masking.
- Long-running work with cheaper subagents doing most tasks; the main session orchestrates and reviews.

## Goals

1. RAW photo capture as DNG, optionally with a processed HEIF alongside.
2. Video capture through Apple's pipeline with every codec, resolution, frame rate and colour option the Duo reports.
3. RAW video and Apple Log 2 through an in-app pipeline that reads RAW sensor frames and processes them on the GPU.
4. A viewfinder LUT for Log footage (built-in Log 2 to Rec. 709, plus imported .cube files), switchable without affecting the recording.
5. Audio input selection, gain, level meters, and live monitoring in connected headphones.
6. Monitoring tools: histogram, waveform, zebra, focus peaking, false colour, frame guides, level.
7. Duo-native behaviour: side strip toolbar, Camera Control, both front cameras, hinge postures, viewfinder on the outer display for the subject when the phone is open.
8. A RAW editor with light, colour, curve and detail controls, masks (subject, sky, background, brush, linear, radial), and Apple Pencil for brushing and healing.

## Non-goals

- App Store, TestFlight, or any other distribution.
- Designed layouts for other iPhones or iPad. The app must not crash there, nothing more.
- Accounts, cloud sync, sharing features, preset stores.
- Cinematic mode, Portrait mode, Live Photos, Photographic Styles.
- Video editing or a timeline.
- Third-party dependencies.
- Matching the colour of Apple's own Log 2 exactly. The deviation gets measured and documented instead.

## Anti-goals (failures even if it works)

- A control that names a format or tool the device cannot actually use at that moment.
- Imitation blur or glass drawn by hand where a system material exists.
- Controls covering the picture on the outer display when the strip or the letterbox bars could hold them.
- A recording that drops frames without saying so.

## Constraints

- iPhone Duo only, iOS 27.1 or later, Xcode 27.2, Swift 6, SwiftUI. Frameworks: AVFoundation, Metal, Core Image, Vision, PencilKit.
- The Simulator has no camera. Every capture path is verified on the physical Duo. UI is verified in the Duo simulator with a stand-in image.
- Apple does not offer ProRAW, ProRes, ProRes RAW or Apple Log on the Duo in its own app. What the device exposes to third-party apps is unmeasured until the probe (P0) runs.
- The RAW pipeline is expected to be limited to about 30 fps, to lose continuous autofocus while recording, and to run hot. These are assumptions from other apps on the same route, to be confirmed by P0.
- Measured in the simulator: outer display 466 x 678 pt at 3x, inner display 669 x 951 pt at 3x. The system strip on the outer display is about 86 pt wide and holds the camera hole, clock and status at its top.

## Projects and order

This is four projects. Each gets its own plan.

| | Project | Output |
|---|---|---|
| P0 | Device probe (throwaway) | A report of every camera, format, codec and colour space the Duo exposes, plus the measured RAW frame rate. Decides what P2 can promise. |
| P1 | Capture app and Duo layout | RAW photos, video through Apple's pipeline, record settings, audio, monitoring tools, Camera Control, postures. |
| P2 | RAW video pipeline | RAW frames to GPU debayer to Log 2 or a RAW container, and the viewfinder LUT for it. |
| P3 | Library and editor | RAW develop controls, masks, Pencil. Gets its own design round first. |

P1 is planned in two parts. P1a, the camera core, is `docs/superpowers/plans/2026-11-09-duocam-camera-core.md`: folded layouts, strip, Record settings from scanned capabilities, RAW photos, video in every reported format. P1b follows once P1a runs on the device: monitoring tools and LUT, audio source and headphone monitoring, manual controls and the adjust ruler, open and seated layouts. Until P1b lands the Monitor item is left out of the strip, and Dolby Vision is not listed as its own colour chip until a device recording shows what HLG clips actually carry.

P0 and P1 are planned and built in parallel. P1 needs nothing from P0 except real data for the capability model, which it stubs with a fixture until the report exists. P2 waits for P0.

### The gate P0 sets for P2

- RAW video and Log 2 stay in scope if the Duo delivers RAW frames at 24 fps or better, at 3840 x 2160 or larger, for 60 seconds with no dropped frames.
- If that only holds at a smaller size, they ship at the sizes that passed and Record settings lists only those.
- If 24 fps does not hold even at 1920 x 1080, RAW video and in-app Log 2 are cut.
- If P0 shows Apple's own pipeline already gives third-party apps Apple Log 2 or ProRes on the Duo, the app uses Apple's for those and P2 builds only RAW video.

## Layout by posture

| Posture | Display | Layout |
|---|---|---|
| Folded, horizontal | Outer, 678 x 466 | Strip on the left. Readouts in the letterbox bars. Viewfinder between them. Primary video layout. |
| Folded, vertical | Outer, 466 x 678 | Strip on the right. Viewfinder above a shutter row. Primary photo layout. |
| Open | Inner, 951 x 669 or 669 x 951 | Viewfinder with a persistent settings panel beside it. The outer display can show the picture to the subject. |
| Seated (partly open) | Inner, split at the fold | Viewfinder on the upper half, control deck on the lower half. |

### Folded, horizontal

```
+--------+--------------------------------------------------------+
| (cam)  | FPS    SHUTTER     00:00:00:00     ISO     WB     TINT  |  56
| 9:41   +--------------------------------------------------------+
| status |                                                        |
|        |                   viewfinder 16:9                      |  333
| [lib]  |                     592 x 333                          |
| [mon]  |                                                        |
| [rec]  +--------------------------------------------------------+
| [lens] | histogram   HEVC 4K Log 2   L/R meters   21 min    (O) |  77
| [mode] |                                                        |
+--------+--------------------------------------------------------+
   86                              592
```

A 16:9 frame fills the width beside the strip and leaves 133 pt of height unused. The readouts live in that space, so nothing overlaps the picture.

### Folded, vertical

```
+--------------------------------+--------+
|                                | (cam)  |
|                                | 9:41   |
|        viewfinder 3:4          | status |
|          380 x 507             | [mode] |
|                                | [lens] |
|                                | [rec]  |
+--------------------------------+ [mon]  |
| SHUTTER   ISO    EV    WB      | [lib]  |
|           ( shutter )          |        |
+--------------------------------+--------+
```

Vertical 9:16 video fills the full 380 x 676 area and the readouts float over it on glass.

### Strip contents

The strip items are native toolbar items, so the system draws them in the side strip with its own glass. Five items, in thumb order from the bottom when horizontal:

1. Mode: Photo or Video.
2. Lens: 0.5x, 1x, 2x, outer front, inner front.
3. Record settings.
4. Monitor tools.
5. Library, shown as the last capture's thumbnail.

Verified in the prototype on the Duo simulator:

- Toolbar items placed with `ToolbarItem(placement: .bottomBar)` and `.axisBehavior(.verticalPreferred)` are drawn by the system as one glass group inside the strip. A custom view (the Library thumbnail) renders there too.
- Horizontal: the strip is on the leading (left) edge, 84 pt wide, and the group sits at its bottom. This is the layout Tanner asked for.
- Vertical: the strip is on the trailing (right) edge and the group sits at its bottom, not under the clock. No toolbar placement moved it under the clock.
- A sheet's close button is also placed in the strip by the system.
- The simulator does not draw the camera hole or clock in the horizontal strip and reports no occlusion region there, so the top of the horizontal strip has to be checked on the device.

If the strip cannot hold five items, or cannot place them at the bottom when horizontal, Mode, Lens and Record settings stay in the strip and Monitor tools and Library move to the bottom letterbox bar. Nothing moves over the picture.

### Picture on the outer display for the subject

When the phone is open, the outer display can show the viewfinder to the person being photographed. iOS 27.1 has a camera capture scene accessory for this, but the SDK does not say which display it appears on. It is a stretch item in P1 with an early spike on the device, and P1 is complete without it.

### Readouts (HUD)

Order follows Blackmagic's: FPS, shutter, timecode, ISO, white balance, tint. The Duo's aperture is fixed, so there is no iris readout. Each readout is a caption over a value in monospaced digits. Tapping one selects it: an adjust ruler appears over the lower edge of the viewfinder and Camera Control switches to that parameter. An Auto button on the ruler returns the parameter to automatic.

Bottom bar: histogram, a format summary that opens Record settings, audio meters, remaining record time, record button.

Photo mode shows shutter speed, ISO, exposure bias, white balance and focus, and the format summary reads like "RAW + HEIF, 48 MP".

### Camera Control

- Press: take the photo or start and stop recording.
- Light press and slide: adjust the selected parameter.
- The parameter selected on screen and the one selected on Camera Control stay the same thing.
- The intended grip: left thumb picks on the strip and the readouts, right index finger adjusts and fires.

### Record settings

One panel of chip grids, read top to bottom. A choice higher up filters the rows below it.

| Row | Example chips |
|---|---|
| Codec | RAW, ProRes, HEVC, H.264 |
| Quality | For ProRes: 4444, 422 HQ, 422, 422 LT, 422 Proxy. For HEVC: bit depth and bitrate tiers. For RAW: container. |
| Resolution | Open gate, 4K, 2.7K, 1080p, 720p, as reported by the selected lens |
| Frame rate | 24, 25, 30, 48, 50, 60, 100, 120, as reported for that resolution |
| Colour | Rec. 709, HLG, Dolby Vision, Apple Log, Apple Log 2 |

- The selected chip uses the prominent glass style. A chip that the current choices rule out is dimmed, and one caption line under the grid says why, for example "RAW records at up to 30 fps."
- A footer states the data rate and remaining time for the current choice.
- The chips are never a fixed list in the shipped app. They are built at launch from what the Duo reports, plus the outputs of the in-app RAW pipeline. The prototype uses a fixture.
- Photo mode has the same panel with rows for format (RAW, RAW + HEIF, HEIF), resolution and lens.

### Monitor and Audio panels

- Monitor: LUT (off, Log 2 to Rec. 709, imported), zebra with threshold, focus peaking, false colour, histogram, waveform, frame guides, grid, level.
- Audio: input list with the current route, gain, format, meters, and a monitoring switch with level. With no headphones connected the switch is disabled and reads "Connect headphones to monitor audio."

On the outer display these open as sheets. On the inner display they are the persistent panel beside the viewfinder.

### States that must be honest

- Camera or microphone permission denied: the viewfinder area says so and offers Settings.
- Low storage: remaining time turns to a warning and recording stops cleanly before the disk fills.
- Heat: a visible notice when the system reports capture pressure, before quality is reduced.
- Dropped frames: a running count during recording, kept with the clip.
- Simulator: the stand-in image is labelled "No camera in Simulator."

## How it is built

Decided:

- SwiftUI with system components and system glass throughout; dark appearance only.
- A capability model built at runtime from device discovery. Every picker renders from it. This is the seam that keeps the UI honest.
- Two recording pipelines behind one recorder interface: Apple's (movie output) and the in-app RAW pipeline.
- A GPU-drawn viewfinder so LUT, zebra, peaking and false colour are passes over the same frames in both pipelines.
- No third-party dependencies.

Left to the builder: module layout, state management details, shader design, file naming on disk, test strategy within Tanner's standing rules.

Verified API notes for the builder are in `docs/research/`.

## Calls made without Tanner (check these)

- Working title "DuoCam".
- Project order P0 to P3, and that the editor gets its own design round.
- The SwiftUI prototype is the design mockup and is throwaway.
- Readouts sit in the letterbox bars instead of over the picture.
- The five strip items and their order.
- Left thumb selects, Camera Control adjusts.
- CinemaDNG as the first RAW video container.
- Minimum iOS 27.1, no dependencies, dark only.
- P0 and P1 run in parallel, and the 24 fps gate for P2 with its fallbacks.
- The strip fallback: Monitor tools and Library move to the bottom bar.
- Showing the picture to the subject on the outer display is a stretch item, not required for P1.

The throwaway prototype lives in `prototype/` and its screenshots in `prototype/screenshots/`.

## Open risks

1. RAW frame rate on the Duo is unknown until P0 runs on the device. If it is too low, RAW video and Log 2 are cut or reduced, and the Record panel must not list them.
2. Log 2 from the in-app pipeline will not match Apple's exactly. A developer doing the same on an iPhone 17 Pro measured about 72 to 74 percent of the native chroma.
3. Whether the Duo has the Camera Control hardware has not been confirmed from a source. The design assumes it does and keeps an on-screen record button either way.
4. Strip placement is confirmed in the simulator for the folded phone only. The open and seated layouts are not built or verified: the simulator's fold state can only be changed in the Device Hub window, not from the command line.
5. Nothing in the SDK headers limits RAW, ProRes or Log to particular models. What the Duo offers is known only at run time, which is what P0 reports.
