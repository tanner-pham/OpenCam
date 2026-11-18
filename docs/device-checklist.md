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

## 10. The recorder

ProRes and Log are recorded by the writer path. HEVC and H.264 in Rec. 709, P3 and HLG stay on the system recorder. Do the first item before anything else.

- [ ] Build `diag/recorder-check` in Release, grant the microphone, and launch it with `-recorderCheck2` pointed at a busy, moving scene. Pull `Documents/recorder-check-2.json` into `docs/research`. Read it against "To confirm on the phone" in the recorder plan before the rest.
- [ ] ProRes 422 HQ 4K 30 HLG for 60 s on 1x: `OC_000n.MOV` plays in Files and in the editor. The `.json` shows `recorder: writer`, `apch`, 3840 x 2160, about 30 fps, `hasAudio` true, `drops.total` 0, and `megabitsPerSecond` beside the chip's figure. Repeat for Proxy, LT and 422.
- [ ] 4K ProRes is offered up to 30 fps until the second on-device check has run. Confirm 4K 60 ProRes is not listed, and note what check 2 says about lifting it.
- [ ] ProRes 422 HQ 4K 30 Rec. 709 (8-bit frames): it records, plays and is tagged Rec. 709. If it fails, note the journal line.
- [ ] ProRes 422 HQ 4K 60 HLG for 60 s, if it is offered after check 2: note `drops`, heat and the count on screen.
- [ ] Log with ProRes and with HEVC at 4K 30, then at 4K 60: the viewfinder shows the normal picture, the clip is flat, a grey card reads near 45 percent, the `.json` colour is Log, and Photos and Files show no HDR badge.
- [ ] Log with HEVC at 4K 30 for 60 s: `drops.renderFailed` is 0 in the `.json`.
- [ ] Log highlights: film a bright window or a lamp. The clip keeps detail in the highlights and does not clip to a flat white patch.
- [ ] A clip in each of the four orientations, and on each camera, is upright. Sound stays in sync over 5 minutes (clap at the start and at the end).
- [ ] Switch HEVC with a look to ProRes and back to HEVC: no "That format could not be used." notice appears.
- [ ] Switch from HEVC in Rec. 709 straight to ProRes in HLG: one blur, the controls return to automatic, and the clip records.
- [ ] HEVC to ProRes and back to HEVC: one blur each way, and HEVC clips are as before (`recorder: system`).
- [ ] Record ProRes on a front camera and an HEVC clip on the same camera: compare their mirroring and orientation. Note any difference.
- [ ] Launch with ProRes saved as the start: the launch line shows the saved start was adopted.
- [ ] Start a recording and stop it the instant it starts: no failure notice appears, and no empty file is left.
- [ ] During a writer clip, one at a time: lock the phone, take a call, fill storage with `-freeSpaceMarginMB`, cover the lens and force heat. Each time the clip is saved, plays whole, and the notice is the right one.
- [ ] Start a writer clip and press the home button within a second: the clip is saved and plays past its first 10 seconds of fragments.
- [ ] "Stop recording" chosen under "When frames drop": provoke a drop (4K 60 Log while the phone is hot). The clip stops, is saved, and the notice reads "Recording stopped. A frame was dropped. Clip saved."
- [ ] Read a ProRes clip's `.json` for its drop counts by reason (`late`, `outOfBuffers`, `discontinuity`, `writerNotReady`, `behind`, `renderFailed`, `other`). Note which reasons appear.
- [ ] The count on the open display, in portrait and landscape, with a slider open: it covers no readout, the format button, the shutter or the slider column.
- [ ] Meters move on the writer path, and the record haptics are felt.
- [ ] Idle with ProRes selected for 5 minutes: note the heat against HEVC.
- [ ] Not covered by either check: sizes other than 1080p and 4K, rates other than 30 and 60, the other four lenses, the writer's HEVC with a tier's bit rate, the effect of the 10 s fragment interval on the finished file and on editors, how Photos, Files and the editor read Log's BT.2020 tags with the Rec. 709 curve, the time a path switch takes, and memory when the writer stalls with late frames kept.

## 11. Fast lens switch (combined back camera)

In video at up to 60 fps the 0.5x, 1x and 2x buttons run on the combined back camera, locked to the lens the button names. Photo mode, rates above 60 fps, the front cameras and a manual shutter or ISO use each lens's own camera, as before. Measured on 2026-11-16 with `-lensCheck` (`diag/dual-wide-check`): no frame is missed on a lens change; the wide lens's first frame comes about 260 ms after the tap at 30 fps, the ultra wide's about 70 ms.

A scripted run on the phone covered the list's machine-checkable half on 2026-11-18 (`-lensRun` on `diag/fast-lens-run` at e895e79, Release, iOS build 24C5037i, 57 of 57 steps as expected). It drove the model through the calls the buttons make and read the camera after each one: 30 lens taps at 4K 30, 4K 60 and 1080p 30 (HEVC and ProRes) with no blur raised, the right camera, lens and zoom, and a `[timing] lens` line each; four clips with 0 frames missing and the lens lock held while recording; the manual shutter's move, Auto, a clip and the next lens tap; 120 fps, photo mode and a front lens on their own cameras behind the blur; 20 taps in a row. It cannot see the picture: every item below that asks how something looks, the Camera Control, VoiceOver, a subject 5 cm away, interruptions, the saved start on 0.5x and 2x, heat, and the format sweep are still to do by hand.

- [ ] In video at 4K 30 and 4K 60, HEVC and ProRes, Rec. 709 and HLG: tap around 0.5x, 1x and 2x. No blur, no frozen picture. Then copy `opencam-errors.log`: each tap wrote a `[timing] lens ... on the combined camera ... ms` line and no `[timing] configure ... (lens` line.
- [ ] 0.5x to 1x: the framing changes at once and the wide lens takes over about a quarter second later. Note how that hand-over looks (sharpness, exposure step, any shift), at 30 and at 60 fps.
- [ ] Twenty fast taps around 0.5x, 1x and 2x, ending on each lens in turn: no crash, and the picture is the lens the button shows.
- [ ] 1x in video against 1x in photo mode, and 1x against 1x with a manual shutter (which uses the wide camera itself): same framing and sharpness? Note any difference.
- [ ] With a hand 5 cm from the lenses, 1x stays the wide lens (blurred, not the ultra wide cropped), also during a recording.
- [ ] A tap to a front lens and back: one blur each way, then the back lens taps are fast again.
- [ ] A rate above 60 fps on 1x: lens taps blur as before.
- [ ] Photo mode: lens taps blur as before, RAW is still offered on 0.5x and 1x, and photo sizes are unchanged.
- [ ] The first manual shutter or ISO value: one blur, then the value holds and the readout shows it. A lens tap after it: one blur, and every control returns to automatic. The next lens tap is fast.
- [ ] Manual white balance, focus and EV on 0.5x, 1x and 2x with exposure automatic: each slider works with no blur. A lens tap returns them to automatic.
- [ ] While recording with exposure automatic: shutter and ISO are dimmed and VoiceOver says "Not available while recording"; white balance, focus and EV still work. With a manual shutter set before recording, shutter and ISO work during the clip.
- [ ] A system clip (HEVC) and a writer clip (ProRes) on each of 0.5x, 1x and 2x: upright, the right lens, sound in sync, `drops.total` 0, and the lens never changes by itself mid clip.
- [ ] The Camera Control's zoom on the combined camera: what it shows on each lens, and whether it can leave the lens the button shows.
- [ ] Launch with the saved start on 0.5x, on 1x and on 2x: the first picture is the right lens, and the launch line shows the saved start was adopted (the first launch after installing this build releases the old start once).
- [ ] A Library visit, a phone call, and locking the phone on each lens: the camera returns on the same lens.
- [ ] A look in video on the combined camera: the look stays across lens taps.
- [ ] Ten minutes on 1x in video: note heat and battery against the build before.
- [ ] The same lens taps at 1080p, at 720p and in P3: no blur, and a `[timing] lens` line each. Only 4K 30 and 60 in HLG and 1080p 30 in Rec. 709 were measured.
- [ ] Run the format sweep (long-press the summary) on 0.5x, 1x and 2x. It now runs options at up to 60 fps on the combined camera. List every failed row: a row that fails here and passed before is the combined camera refusing a format.
- [ ] If a format ever shows "That format could not be used." on a back lens, choose it again: the second try uses the lens's own camera and should work. Note the format and the journal line.
- [ ] Tap a lens and drag the shutter slider straight away: one blur, the shutter holds, and no "That setting could not be applied." notice.
- [ ] Set the shutter by hand, set white balance by hand, set the shutter back to Auto, record a clip and stop it: no blur at the stop, and the white balance is still the one set. The next lens tap blurs once.
- [ ] The launch line's time to the `lenses` mark against the build before: the combined camera is read there.

## 9. Things to decide after holding it

- [ ] Where should the look's name live? The summary grows a line: a four-line pill in vertical video, and the open phone's photo picture shrinks a few points.
- [ ] Do the folded phone's bottom controls sit too close to the home indicator? They reach into the 34 pt bottom inset by design (`isFoldedDisplay` in `CameraLayout.barInsets`).
- [ ] A photo taken with a look loses the HDR gain map and depth data. RAW + HEIF keeps an untouched DNG. Acceptable?
- [ ] Remove look asks first; Apply look asks only when it replaces edits. Keep?
- [ ] Applying to nothing reads "Applied to 0 photos. 2 videos were skipped." or "No photos changed. 2 videos were skipped."?
- [ ] Exports keep location. Strip it?
