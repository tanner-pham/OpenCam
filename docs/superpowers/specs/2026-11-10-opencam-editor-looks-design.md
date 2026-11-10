# OpenCam editor and looks design

Status: draft written overnight on 2026-11-10 without Tanner. Everything under "Calls made without Tanner" needs his check before it is treated as approved. Engine work that does not depend on those calls may be built ahead.
Parent spec: `docs/superpowers/specs/2026-11-09-duo-camera-design.md` (this is its project P3, widened by the request below).

## What Tanner asked for

"Start working on the lightroom esc software and tooling to edit photos on the go. Remember that this should include making a look, saving it, and applying it in the viewfinder and applying it when shooting raw or jpeg and applying it to other photos as well."

From the parent spec: Lightroom-level colour control and masking for the RAW photos, Apple Pencil for correction and touch-ups, on-device subject masking.

## Intent

Edit photos on the phone with the control of a desktop RAW editor, and turn any edit into a look: a named, saved set of adjustments. A look is chosen once and then shows live in the viewfinder, is applied to what the camera saves, and can be applied to any other photo in the library.

## Goals

1. Non-destructive editing of every photo OpenCam captured or imported: light, colour, detail and effects first; colour mixer, tone curve and colour grading next; masks and healing last.
2. Looks: make one from the current edit, name it, save it, rename, duplicate, delete.
3. A look applied in the viewfinder, live.
4. A look applied at capture: baked into HEIF or JPEG; kept beside an untouched DNG for RAW.
5. A look applied to other photos, one or many at once.
6. RAW development from the DNG, not from an embedded preview.
7. Masks: subject, sky, background and people found on-device; brush, linear and radial drawn by hand; each with its own adjustments.
8. Apple Pencil for brushing masks and for healing.

## Non-goals

- Video editing or looks baked into video. A look in the viewfinder while recording video is preview only.
- Syncing looks or edits anywhere.
- A preset store, sharing looks, importing third-party preset formats.
- Generative fill or object removal beyond a clone-style heal.
- Layers, text, stickers, collage.

## Anti-goals

- An edit that cannot be undone back to the original file.
- A look that renders differently in the viewfinder, in the saved file and in the editor. One renderer serves all three.
- Sliders that lag behind the finger on a 48 MP photo. The editor works on a screen-sized proxy and renders full size on export.
- A control for a tool that is not built yet.

## The model

| Thing | What it is | Where it lives |
|---|---|---|
| Adjustments | Plain values: exposure, contrast, highlights, shadows, whites, blacks, temperature, tint, vibrance, saturation, sharpening, noise reduction, grain, vignette; later the colour mixer, tone curve and colour grading | In memory; inside a look or an edit |
| Look | A name and the adjustments that make sense on any photo. No crop, no masks, no healing. | `Documents/Looks/<id>.json` |
| Edit | One photo's adjustments, the look it started from (copied in, not linked), crop, masks, heal strokes | `Documents/Captures/OC_0001.edit.json`, beside the original |
| Original | The captured or imported file. Never rewritten. | `Documents/Captures/` |

A look is copied into the edit when applied. Changing a look later does not silently change photos that already used it.

## One renderer

```
original (HEIF, JPEG, or DNG through the RAW developer)
   -> linear working image
   -> colour stage: everything that maps a colour to a colour, compiled into one 3D lookup table
   -> spatial stage: sharpening, noise reduction, grain, vignette
   -> masked local adjustments (same two stages, limited by a mask)
   -> output (screen proxy, viewfinder frame, exported HEIF or JPEG)
```

- The colour stage of a look compiles to a single 33-point 3D table. That table is what makes the viewfinder cheap: one lookup per frame.
- The table works in Display P3, the colour space iPhone photos are in, so wide-gamut colours are not clipped. Luma weights are the Rec. 709 ones applied to P3 values, a deliberate simplification.
- The viewfinder applies the colour table and the vignette. It skips sharpening, noise reduction and grain, and says nothing that implies otherwise.
- The compiler and the colour maths are pure and unit-tested with known values (an identity look returns the image unchanged; plus one stop doubles linear values; saturation zero gives equal channels).

## Where a look applies

| Place | Behaviour |
|---|---|
| Viewfinder | Camera frames pass through the look's colour table and are drawn on the GPU. This replaces the plain preview layer and is the same viewfinder the Log preview LUT and the monitoring tools will use later. In the Simulator the stand-in picture goes through the same path, so it can be verified without a camera. |
| Shooting HEIF or JPEG | The saved file has the look baked in. What the viewfinder showed is what the file contains. |
| Shooting RAW + HEIF | The DNG is untouched. The HEIF has the look baked in. |
| Shooting RAW | The DNG is untouched. An edit file beside it carries the look, so OpenCam shows and exports it with the look, and removing the look loses nothing. |
| Other photos | Select one or many in the library, choose a look. Each gets an edit file with the look copied in. |

## Screens

- **Library**: a grid of everything in Captures, drawn with its edits. Select mode for applying a look to many. Import brings photos in from the Photos library as new originals.
- **Editor**: the photo with a panel of grouped sliders. Groups: Light, Colour, Detail, Effects, then Mix, Curve, Grading, Masks as they are built. Press and hold the photo for the original. A reset per slider and for the whole edit. Looks has its own group: thumbnails of every saved look on this photo, and "Save as look".
  - Open phone (inner display): photo beside the panel.
  - Folded (outer display): photo above the panel.
- **Camera**: a Look item in Record settings for photo and video modes: None, then the saved looks. The format summary shows the look's name when one is on.

All of it uses the system components, system glass and Theme already in the app.

## Order of work

| Plan | Contents | Verifiable in the Simulator |
|---|---|---|
| E1 | Adjustments, looks, edits and their files; colour compiler and renderer; library with import; editor with Light, Colour, Detail, Effects; make, save, apply and manage looks; apply to many; export | Yes, fully |
| E2 | GPU viewfinder; look picker in the camera; look baked at capture; edit file for RAW | The stand-in path and the baking, yes. Live camera frames, no. |
| E3 | RAW development from DNG; colour mixer; tone curve; colour grading | Needs DNG files from the device |
| E4 | Masks (found on-device and drawn), Pencil brushing, healing | Mostly; the on-device finders need real photos |

## Calls made without Tanner

- A look is copied into a photo's edit, not linked to it.
- Looks carry no crop, masks or healing.
- HEIF and JPEG saved with a look have it baked in; no unprocessed copy is kept unless the format also includes RAW.
- A look in the viewfinder during video is preview only; the recorded video is unchanged.
- The viewfinder shows the look's colour and vignette but not sharpening, noise reduction or grain.
- JPEG is added as a photo format beside HEIF so "RAW or JPEG" is literal.
- No built-in looks ship. The list starts with "None".
- Healing is a clone-style heal, not generated content.
- Import from the Photos library is how "other photos" from outside OpenCam get in.
- The order E1 to E4, and that E1 starts before this design is approved because none of it needs the camera.
- The colour table works in Display P3, not sRGB.
- The library also lists video clips, so they stay reachable once the Library screen replaces the last-capture preview. Clips are not editable; "Apply look" skips them and says so.
- "Remove look" clears the photo's whole edit.
- The exact slider formulas (in plan E1). They are simple and pinned by tests; they are not a match for any other editor's sliders.

Plan for E1: `docs/superpowers/plans/2026-11-10-opencam-editor-looks-e1.md`.

## Open risks

1. The GPU viewfinder changes how the camera core draws its preview. It must not cost frames or battery compared with the preview layer; that can only be measured on the device.
2. Colour accuracy between the viewfinder's table and the full renderer depends on doing both in the same working colour space. Tests pin the maths; the eye on the device confirms it.
3. RAW development quality depends on Apple's RAW engine for the Duo's sensor, unmeasured until there are DNG files from the phone.
4. Subject and sky finders come from the system and their quality on real photos is unknown until tried.
