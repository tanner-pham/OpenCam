# OpenCam: first run on the phone

Build the branch `feat/looks-in-camera` from Xcode onto the Duo.
Nothing here has run on a phone yet.
A failed check is information, not an emergency: note what happened and move on.

## 1. Before the app: the probe

- [ ] Run `probe/DuoCamProbe.xcodeproj` on the phone: allow camera and microphone, tap "Run probe", wait for "Done".
- [ ] Copy `duocam-probe-report.json` to the Mac. It is in the probe's Documents folder: Files > On My iPhone > DuoCamProbe should show it; if not, download the app's container from Xcode's Devices window.
- [ ] `cameras`: note each `deviceType` and `position`, and which front camera is the outer one.
- [ ] `summary.proResRawInMovieOutputCodecs`, or `aprn` / `aprh` in `movieCodecTypes`. If absent, no RAW video.
- [ ] `summary.fastestSustainedRawFps` with its size and method.
- [ ] `colorSpaces` per format (AppleLog, AppleLog2, HLG, P3), and `summary.cameraControlSupported`.

## 2. First launch and the plain camera (no look)

- [ ] First launch asks for camera, then microphone. Allow both.
- [ ] "Reading camera formats…" shows once, then the picture. A second launch skips it.
- [ ] The picture is upright in all four orientations on the folded phone, nothing over it.
- [ ] The lens menu lists 0.5x, 1x, 2x, Outer Ultra Wide Camera and Inner Ultra Wide Camera, with 1x selected.
- [ ] The strip has three items: Mode, Lens, Library, none under the camera hole or clock. Record settings opens from the format button.
- [ ] On the folded phone, in portrait and landscape, each of the three strip items responds to a tap: Mode switches between photo and video with no menu, Lens opens its menu, Library opens the Library. The format button opens Record settings in both modes.
- [ ] Change lens and mode. Record settings lists only what that lens offers.
- [ ] Copy `capabilities.json` (Files > On My iPhone > OpenCam) to the Mac. Its codecs and colours per lens should match the probe.
- [ ] Background and return, fold and unfold: the preview resumes. Note any notice.
- [ ] Camera off in Settings: "Camera access is off." with a working "Open Settings". Microphone off: bottom bar says "No microphone access".

## 3. Photos

- [ ] 1x, RAW + HEIF at 48 MP: one press writes `OC_000n.DNG` and `.HEIC` (Files > OpenCam > Captures). On the Mac, `mdls -name kMDItemPixelWidth -name kMDItemPixelHeight` on the DNG shows the sensor size.
- [ ] RAW alone and HEIF alone each write the right file. No size offered fails.
- [ ] RAW and RAW + HEIF are offered on 0.5x and 1x only. 0.5x RAW writes a DNG. On 2x the RAW chips read "RAW needs the 0.5x or 1x lens." and HEIF works.
- [ ] Both front lenses are HEIF only: HEIF works and no RAW is offered.
- [ ] Ten quick presses give ten distinct numbers, no overwrite, no crash.
- [ ] The strip thumbnail shows the newest photo and opens it.
- [ ] Camera Control, if present: a full press takes a photo; a light press shows zoom and exposure sliders.
- [ ] ISO, shutter, WB and tint change between a bright window and a dark corner.

## 4. Video

- [ ] HEVC High 4K 30 Rec. 709 on 1x for 10 s: the `.MOV` and `.json` appear. The `.json` shows `hvc1`, 3840 x 2160, about 30 fps, `droppedFrames` 0, `hasAudio` true, `megabitsPerSecond` near 27. Repeat at Max and Low; identical numbers mean bitrate is ignored.
- [ ] 24 fps records at 24.
- [ ] Try each codec and colour the lens offers (HEVC, ProRes, ProRes RAW if listed; Rec. 709, P3, HLG, Apple Log, Apple Log 2). `actual.colour` in the `.json` matches the pick.
- [ ] Record HLG HEVC and check on the Mac (`mediainfo`) for Dolby Vision metadata.
- [ ] Start and stop with the button and Camera Control.
- [ ] Audio meters move with speech. Microphone off: the clip records, `hasAudio` false.
- [ ] Time left looks right and warns when low.
- [ ] Launch with `-freeSpaceMarginMB 300` (Xcode scheme argument), record ProRes 4K to the end: "Recording stopped. Storage is full. Clip saved." and the clip plays.
- [ ] While recording, one at a time: swipe home, fold or unfold, take a call. Each clip plays, has a `.json`, and the notice says it was saved.
- [ ] A long 4K ProRes recording while warm: note the first pressure notice.
- [ ] Long-press the format summary for the sweep. Run it on 1x, 0.5x, 2x and one front lens. Progress reads "n of N" and each run writes a `sweep-` report. A mid-run Cancel writes `cancelled: true`. List every failed row and reason.
- [ ] Pick a failed combination: Record settings reads "This combination did not record in the last format sweep." and the summary takes the warning style.
- [ ] With ProRes 4K chosen on 1x, switch to a front lens: no crash.

## 5. The open phone

- [ ] In photo and video mode, in both orientations, every control sits fully on screen, none cut off.
- [ ] Every control responds.
- [ ] Confirmations are popovers with no cancel button; tapping outside cancels.

## 6. Library, editor and looks

- [ ] Close the Library: the preview returns without a relaunch.
- [ ] RAW + HEIF is one item and opens with the HEIC. A DNG alone opens and matches its thumbnail.
- [ ] Sliders follow your finger without lag. Press and hold shows the original. Double-tap resets. Done refreshes the thumbnail.
- [ ] A saturated photo (red flower), unedited: editor, thumbnail and export match Photos, no clipping.
- [ ] Export a 48 MP photo: it opens in Photos at full size. Share sheet and Save to Files work.
- [ ] A clip plays. Deleting it removes the MOV and its `.json`.
- [ ] On the inner display the picture sits beside the 320 pt panel.
- [ ] Import through the system photo picker works.
- [ ] Look menu: Rename, Duplicate, Delete and their prompts. Apply look and Remove look on selected photos.

## 7. Looks in the camera

First make a look in the editor, such as "Warm fade".

- [ ] With None, viewfinder, frame rate and photos feel as before.
- [ ] Pick the look: it shows within a moment, upright and level in all four orientations. Back to None shows the plain preview at once, no flicker, never black.
- [ ] Front camera, all four orientations: upright and mirrored like the plain preview (`OpenCam/Capture/FrameOrientation.swift`).
- [ ] Change lens, mode, resolution and frame rate (HEVC and ProRes, Rec. 709 and P3): the look stays. A format that cannot take it shows "The look cannot be shown in the viewfinder with this format." and the plain preview. The next change tries again.
- [ ] Smooth at 30 and 60 fps, no strip stalls, no dropped frames (`OpenCam/Capture/FramePipeline.swift`).
- [ ] Background and return, open and close the Library: frames resume with no false notice.
- [ ] HEIF with a look: `OC_000n.HEIC` shows the look, upright, with date and lens data, matching the viewfinder.
- [ ] RAW + HEIF with a look: DNG plain, HEIC with the look, one Library item.
- [ ] RAW with a look: the DNG is untouched, `OC_000n.edit.json` names the look, and "Remove look" returns the plain DNG.
- [ ] 48 MP HEIF with a look: the next press is not blocked, a lens change does not freeze the viewfinder. Note press to thumbnail time.
- [ ] Quick photos with a look: the strip shows the newest.
- [ ] Video with a look: shown while recording, absent from the clip, no dropped frames.
- [ ] Battery and heat: ten minutes with a look against ten with None. Note both.

## 8. Manual controls

Tap SHUTTER, ISO, EV, WB, TINT or FOCUS to open its slider. The folded phone shows it in the strip. The open phone shows it in a glass column at the edge of the picture. Everything is automatic at launch.

- [ ] Shutter, ISO, EV, WB, tint and focus each change the picture and their readout when dragged.
- [ ] Each slider moves to both ends on each of the five lenses with no crash.
- [ ] Both front lenses offer no focus slider.
- [ ] 24 fps video with the shutter at its slowest stops at 1/24. The clip's `.json` still reads 24 fps.
- [ ] A video's frame rate in the clip's metadata (`mediainfo`) is unchanged after shutter and ISO were set by hand before the clip and during it.
- [ ] Photo mode, shutter at 1 s, then at 1/60: the preview returns to full rate. Auto does the same.
- [ ] A HEIF taken at a manual 1/1000 in a dim room is as dark as the viewfinder.
- [ ] White balance set by hand before and during a ProRes RAW clip is still set after it.
- [ ] Auto during a ProRes RAW clip changes nothing until the clip ends, then white balance is automatic.
- [ ] While shutter or ISO is set by hand, EV reads `--`, is dimmed and does not open.
- [ ] While shutter or ISO is set by hand, the Camera Control's EV is greyed out.
- [ ] EV moved on the Camera Control shows in the app's EV readout.
- [ ] A lens, mode or format change returns every readout to live values and closes the slider.
- [ ] Background the app and return: the manual values are still set.
- [ ] Quit the app after setting values by hand and launch it again: everything is automatic.
- [ ] A drag gives a haptic tick at each step on the folded phone's strip.
- [ ] Whether the step haptics are heard in a clip. Note it.
- [ ] VoiceOver reads each slider in the strip as adjustable, and the Auto and close buttons by name.
- [ ] With a slider open, bring up the Camera Control's full-screen controls: the app's slider closes.
- [ ] Landscape photo shows the video readouts, so EV and FOCUS cannot be opened there. Decide whether it should show the photo readouts.
- [ ] On the open phone, in portrait and landscape, video and photo, the column appears beside the strip when there is one, drags, and covers no readout, the format button or the shutter.
- [ ] On the open phone, the column does not cover a camera notice.
- [ ] On the open phone, tapping Lens or Mode with the column open closes it.
- [ ] Whether `supportsExposureModeCustom(lensAperture:duration:iso:)` accepts a shutter with automatic ISO. Note the result for each lens.

## 9. Things to decide after holding it

- [ ] Where should the look's name live? The summary grows a line: a four-line pill in vertical video, and the open phone's photo picture shrinks a few points.
- [ ] Do the folded phone's bottom controls sit too close to the home indicator? They reach into the 34 pt bottom inset by design (`isFoldedDisplay` in `CameraLayout.barInsets`).
- [ ] A photo taken with a look loses the HDR gain map and depth data. RAW + HEIF keeps an untouched DNG. Acceptable?
- [ ] Remove look asks first; Apply look asks only when it replaces edits. Keep?
- [ ] Applying to nothing reads "Applied to 0 photos. 2 videos were skipped." or "No photos changed. 2 videos were skipped."?
- [ ] Exports keep location. Strip it?
