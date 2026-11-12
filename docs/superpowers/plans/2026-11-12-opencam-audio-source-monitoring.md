# OpenCam Audio Source and Headphone Monitoring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans. Steps use checkbox syntax. Paths are relative to the worktree root, `/Users/tannerpham/CS Projects/DuoCam/.claude/worktrees/feat+camera-core`.

**Goal:** In video mode, Record settings gets an Audio section where the owner picks the microphone and can hear it live in connected headphones.

**Architecture:** Everything is new files. A pure `AudioState` turns the route, the choice and the camera's liveness into chips, notices and an `AudioPlan`; `AudioPlan.steps(from:)` is the ordered list of device calls. A MainActor `AudioModel` owns the state and sends plans through a tiny `AudioDevice` protocol on one serial chain. `SystemAudioDevice` (an actor) is the only code that touches `AVAudioSession`, `AVAudioEngine` and the capture session's one flag, reached through a `CameraSession` extension in a new file. `CameraModel`, `CameraSession.swift`, `SessionConfigurator` and its fake are not edited.

**Tech Stack:** Swift 6 (MainActor default isolation), SwiftUI, AVFAudio, AVFoundation, Swift Testing. No dependencies.

**Spec:** The owner: "audio source choice and headphone monitoring". The controller's seven decisions, with these corrections from the headers (H numbers below):

- **Decision 2 is wrong for a chosen source.** Under automatic configuration the capture session "picks an appropriate microphone and polar pattern to match the video camera being used" (H1), so a preferred input or data source is not ours to keep. Smallest change: **Automatic** (the default, and the fallback) leaves the capture session in charge exactly as today. A chosen source sets `automaticallyConfiguresApplicationAudioSession = false` only while the camera runs, then sets the preference. The app never calls `setCategory`, `setMode` or `setActive`: H1 names only the category (PlayAndRecord), not the mode or options, so today's values cannot be reproduced by hand; they are inherited from the capture session's last start and journalled once. When the camera stops, the flag goes back to true so every start is configured and activated as today, and the pin is set again once it runs.
- **Monitoring needs no ownership change.** PlayAndRecord is guaranteed (H1), the shared session allows "simultaneous play back and recording" (H2), and the engine's input is allowed by the category (H9). No header says two input clients may run together and none forbids it; a refusal arrives as a thrown start (H10). So monitoring is built and guarded, not blocked, and "heard while recording" is a phone check.
- **Bluetooth is read, never forced.** A Bluetooth microphone needs `allowBluetoothHFP` and Bluetooth headphones need `allowBluetoothA2DP`, both off by default in PlayAndRecord (H8); the headers do not say whether the capture session sets them. The rows show what the session reports.
- **Decision 4:** `availableInputs` lists only usable inputs (H5), so the only dimmed state is no microphone access. The built-in microphone is one chip per data source.
- **Decision 6:** nothing is saved, the monitoring preference included (a remembered "on" at a launch without headphones needs more than one line).
- Record settings cannot open while recording (`CameraModel.swift:303-305`), so nothing here can change mid-clip; a monitor already on keeps playing through a recording.

**Header facts** (`$(xcrun --sdk iphoneos --show-sdk-path)/System/Library/Frameworks/`, iPhoneOS27.2; `AVCaptureSession.h` under `AVFoundation.framework/Headers/`, the rest under `AVFAudio.framework/Headers/`):

- H1 `AVCaptureSession.h:552-554`: automatic configuration, quoted above; when off the session "will not change any of its properties. If the session is not set up correctly for input, audio recording may fail."
- H2 `AVCaptureSession.h:542-544`: `usesApplicationAudioSession`, default YES. `:562-564` mixing, `:568-569` Bluetooth high quality recording (iOS 26). Nothing audio is new at iOS 27 in this header.
- H3 `AVAudioSession.h:150-160`: `setPreferredInput` throws; nil clears; no effect if the port is already routed, otherwise a route change.
- H4 `AVAudioSessionRoute.h:204`, `:98`, `:25-30`, `:215-222`: `dataSources` (nil when none), `orientation`, `setPreferredDataSource` throws, must be one of `dataSources`, nil clears, no route change until the port is activated with `setPreferredInput`.
- H5 `AVAudioSession.h:470-479`: `availableInputs` is nullable and "only applies to the session's current category and mode". `AVAudioSessionTypes.h:237` route change, `:386-391` available inputs change (iOS 26, no payload), `:248-253` media services reset ("re-initialize any audio objects").
- H6 `AVAudioSessionTypes.h:27, 30, 61, 64`: input ports. `:38, 41, 56, 61, 64`: headphone outputs. `:44, 47`: receiver and speaker.
- H7 `AVAudioSession.h:30`, `AVAudioSessionRoute.h:72, 155, 236`: the session, port, data source and route classes are `NS_SWIFT_SENDABLE`.
- H8 `AVAudioSessionTypes.h:520, 572`.
- H9 `AVAudioEngine.h:526-545, 547-571, 574-590`: input and output nodes exist only if the category allows; check the format for a non-zero rate and channel count, otherwise "an error (when possible) or an exception"; the main mixer follows the output format.
- H10 `AVAudioEngine.h:283-295`: `connectNode(_:to:format:)` throws, new at iOS 27 (`:281` deprecates the old one). `:427-448`: `start` throws for the graph, an audio session error or the driver.
- H11 `AVAudioEngine.h:1036-1062`: on a hardware format change the engine stops itself; input chains reconnect at the new rate; never release the engine in the handler (it runs on an internal queue).
- H12 `AVAudioSession.h:310-311`: `setPreferredIOBufferDuration` throws, "actual may be different". `:413` `outputLatency`.
- H13 `AVAudioSession.h:116-119`: the haptics flag.
- H14 `AVCaptureAudioPreviewOutput.h:26`: unavailable on iOS, so the capture stack has no monitor output there. `AVAudioSessionTypes.h:229`: the interruption notification is deprecated at 27.0 and is not used.

## Global Constraints

- Branch `feat/audio-source` from `feat/camera-ui-cleanup`. House rules apply: strict Swift 6, no force unwraps or `try!`, one type per file, errors as `[Module:Function] Description — {context}`, no `@unchecked Sendable`, `nonisolated(unsafe)` or `@preconcurrency import`, conventional commits, no attribution lines.
- The parallel recorder build: do not edit `CameraSession.swift`, `SessionConfiguration.swift`, `SessionConfigurator.swift`, `SessionEvent.swift`, `MovieRecorder.swift`, `CameraModel.swift`, `CameraModel+Recording.swift`, `RecordSettingsSheet.swift`, `CameraRootView.swift`, the folded layouts, `FakeSessionConfigurator.swift`, `LaunchConfigTests.swift`. Shared files are touched only at the four named insertion points (Tasks 2 to 4). The project uses synchronized folders, so `project.pbxproj` is not edited.
- Risk rule: with Source on Automatic and monitoring off, no audio session or capture session call is made. `CameraSession.allowHapticsWhileRecording()` stays as it is and still runs before every recording; nothing here changes the category, so nothing here clears its flag.
- Nothing in `OpenCam/Audio` reads `isRecording`, `SessionConfiguration`, `SavedSelections` or `SavedStart`, or causes a `configure`.
- Tests: `scripts/test.sh <Suite>`; whole suite `scripts/test.sh`. Device compile after Task 4: `xcodebuild -project OpenCam.xcodeproj -scheme OpenCam -sdk iphoneos -destination generic/platform=iOS -derivedDataPath .build CODE_SIGNING_ALLOWED=NO build`, 0 warnings.
- Simulator: "OpenCam Dev" through `scripts/sim-udid.sh`. Tap checks: one action, wait 2 seconds, `xcrun simctl io "$(scripts/sim-udid.sh)" screenshot --display=1 <file>`, read the PNG. Screenshots in `docs/screenshots/audio/`, names `audio-…`.
- Copy in the tasks is final. Nothing about the phone is claimed as verified.

## Review Focus

1. **Recording changes although nothing was chosen.** Pinned by `AudioPlanTests.theDefaultPlanHasNoSteps` and `AudioModelTests.nothingChosenSendsOnlyTheDefaultPlan`.
2. **The microphone plays from the speaker, or keeps playing after the headphones left.** Pinned by `AudioStateTests.monitoringIsOfferedOnlyWithHeadphones` and `monitoringTurnsItselfOffWhenHeadphonesGoAway`.
3. **The row names a microphone the session is not using:** a source that vanished or was refused stays selected, or the fallback loops. Pinned by `AudioStateTests.aChosenSourceThatDisappearsFallsBackToAutomatic` and `AudioModelTests.aRefusedPinFallsBackOnce`.

---

### Task 1: The pure state

**Files:** Create in `OpenCam/Audio/`: `AudioPortKind.swift`, `AudioDataSource.swift`, `AudioInput.swift`, `AudioRoute.swift`, `AudioPin.swift`, `AudioStep.swift`, `AudioPlan.swift`, `AudioDeviceError.swift`, `AudioState.swift`. Tests: `OpenCamTests/AudioStateTests.swift`, `AudioPlanTests.swift`.

**Interfaces. Consumes:** `Chip`, `CameraPhase`, `CaptureMode`. **Produces** (all `nonisolated`, `Equatable`, `Sendable`):

```swift
enum AudioPortKind { case builtIn, wired, usb, bluetooth, other
    init(portType: String)   // AVAudioSession.Port raw values, H6
    var title: String }      // "Built-in", "Wired", "USB", "Bluetooth", "External"
struct AudioDataSource { let id: Int; let label: String
    init(id: Int, name: String, orientation: String?) }   // "Front", "Back", "Bottom", "Top", "Left", "Right"; else name
struct AudioInput { let uid: String; let kind: AudioPortKind; let name: String; let dataSources: [AudioDataSource] }
struct AudioRoute { var inputs: [AudioInput] = []; var outputs: [AudioPortKind] = []
    var headphones: AudioPortKind? }   // at least one output, and every output is wired, usb or bluetooth
struct AudioPin { let portUID: String; let dataSourceID: Int?; var chipID: String }   // "uid" or "uid#3"
enum AudioStep { case stopMonitor, clearPin, captureConfiguresAudio(Bool), pin(AudioPin), startMonitor }
struct AudioPlan { var pin: AudioPin? = nil; var captureConfiguresAudio = true; var isMonitoring = false
    func steps(from applied: AudioPlan) -> [AudioStep] }
enum AudioDeviceError: Error { case inputMissing(uid: String), pinRefused(reason: String), monitorRefused(reason: String)
    var description: String }
struct AudioState {
    private(set) var route = AudioRoute(); private(set) var pinned: AudioPin?; private(set) var wantsMonitor = false
    var isCameraLive = false; var hasMicrophone = true
    var sourceChips: [Chip]; var selectedSourceID: String; var sourceReason: String?
    var monitorChips: [Chip]; var selectedMonitorID: String; var monitorReason: String?
    var plan: AudioPlan
    mutating func select(chipID: String)
    mutating func setMonitor(_ isOn: Bool)
    mutating func routeChanged(to route: AudioRoute) -> String?   // the notice, if something was taken away
    mutating func failed(_ error: AudioDeviceError) -> String
    static func isLive(phase: CameraPhase, mode: CaptureMode, isInterrupted: Bool) -> Bool
}
```

Rules.
- Source chips: `automatic` ("Automatic", detail "Matches the camera"), then per input one chip per data source (title `kind.title`, detail the source's label), or one chip (detail the port's name) when it has none. `select` looks the id up among the chips the route offers; an unknown or dimmed id changes nothing.
- Monitor chips: `off` "Off", `on` "On". "On" is available only when `hasMicrophone` and `route.headphones != nil`.
- Reasons. Both rows without access: "No microphone access." Monitor without headphones: "Connect headphones to monitor." Monitor with Bluetooth headphones: "Bluetooth headphones add a delay."
- `plan`: `pin = pinned`; `captureConfiguresAudio = !(pinned != nil && isCameraLive)`; `isMonitoring = wantsMonitor && isCameraLive && hasMicrophone && route.headphones != nil`.
- `routeChanged`: a pinned port or data source no longer listed gives Automatic and "Microphone disconnected. Source is Automatic."; `wantsMonitor` without headphones gives off and "Headphones disconnected. Monitoring is off."; both at once returns the microphone line. Monitoring stays off when headphones return.
- `failed`: a pin error gives Automatic and "That microphone could not be used. Source is Automatic."; a monitor error gives off and "Monitoring could not start."
- `steps`: `stopMonitor` first; taking over is `captureConfiguresAudio(false)` then `pin` (always set again on take-over); handing back is `clearPin` (only when the target has no pin) then `captureConfiguresAudio(true)`; `startMonitor` last.
- `isLive`: phase `.ready` or `.simulator`, mode `.video`, not interrupted.

- [ ] **Step 1: Failing tests.** `AudioStateTests`: `theBuiltInMicrophoneIsOneChipPerDataSource` (built-in with three sources plus a USB port: ids `automatic, mic#1, mic#2, mic#3, usb`; details `Matches the camera, Front, Back, Bottom, <port name>`; `automatic` selected); `portTypesMapToKinds` (every port in H6; HDMI, AirPlay, line out and car audio are `other`); `aDataSourceWithNoOrientationKeepsTheSystemsName`; `withoutMicrophoneAccessEveryChipIsDimmed` (both reasons, plan is `AudioPlan()`); `aChosenSourceSurvivesARouteChangeThatKeepsIt`; `aChosenSourceThatDisappearsFallsBackToAutomatic`; `aDataSourceThatDisappearsFallsBackToo`; `monitoringIsOfferedOnlyWithHeadphones` (speaker, receiver, no output, and headphones plus a speaker: dimmed with the reason and `setMonitor(true)` changes nothing; wired: offered; Bluetooth: offered with the delay line); `monitoringTurnsItselfOffWhenHeadphonesGoAway`; `aHeadsetUnpluggedSaysTheMicrophoneWentAway`; `aStoppedCameraPausesMonitoringAndKeepsTheChoice` (not live: not monitoring, capture configures, pin kept, no notice; live again: as before); `aRefusedPinFallsBackAndARefusedMonitorTurnsOff`; `liveIsVideoOnARunningCamera`; `noStringHasAnEmDash`. `AudioPlanTests`: `theDefaultPlanHasNoSteps` (and a fresh state with any route, live, has plan `AudioPlan()`); `pinningTakesOverThenSetsTheInput`; `backToAutomaticClearsThePinThenHandsBack`; `aParkedPinOnlyHandsBackAndIsSetAgainOnReturn`; `monitoringStopsFirstAndStartsLast`.
- [ ] **Step 2: Implement,** run `scripts/test.sh AudioStateTests` and `AudioPlanTests`.
- [ ] **Step 3: Commit.** `feat(audio): add the pure source and monitoring state`

### Task 2: The model, the device protocol and the simulated device

**Files:** Create `OpenCam/Audio/AudioChange.swift`, `AudioDevice.swift`, `AudioModel.swift`, `SimulatedAudioDevice.swift`. Modify `OpenCam/App/LaunchConfig.swift` at two points: two properties directly after `var keepsSweepClips = false`, and two parse lines directly before `return config` (after the `-keepSweepClips` line; unscripted, like their neighbours). Tests: create `OpenCamTests/FakeAudioDevice.swift` (an actor, as `FakeSessionConfigurator`), `AudioModelTests.swift`, `SimulatedAudioDeviceTests.swift`.

**Interfaces. Consumes:** Task 1. **Produces:**

```swift
nonisolated enum AudioChange: Sendable, Equatable { case routeChanged, failed(AudioDeviceError) }
nonisolated protocol AudioDevice: Sendable {
    var changes: AsyncStream<AudioChange> { get }
    func route() async -> AudioRoute
    /// Runs `plan.steps(from:)` against what it last applied. On a throw, what was applied so far stands.
    func apply(_ plan: AudioPlan) async throws(AudioDeviceError)
}
@Observable final class AudioModel {
    private(set) var state = AudioState(); private(set) var notice: String?
    init(device: any AudioDevice)
    func run() async          // follows device.changes for as long as the calling task runs
    func select(chipID: String); func setMonitor(_ isOn: Bool)
    func setCamera(isLive: Bool, hasMicrophone: Bool)
    func settle() async       // waits for the queued syncs; for tests
}
nonisolated struct SimulatedAudioDevice: AudioDevice { init(config: LaunchConfig) }
// LaunchConfig: var hasWiredMicrophone = false   // -wiredMic on (Simulator only)
//               var hasHeadphones = false        // -headphones on (Simulator only)
```

Rules. Each mutator reduces the state at once (a tap clears `notice`), then queues one sync on a serial chain (the tail pattern of `CameraModel.configureTask`). A sync reads `device.route()`, reduces `routeChanged`, calls `apply(state.plan)`; on a throw it reduces `failed`, sets the notice and applies once more. `.failed` from `changes` is reduced the same way. The model keeps no memo of what it sent; the device skips what is already applied. The simulated device lists Built-in with Front, Back and Bottom, adds "Headset microphone" (wired) by flag, reports headphones or the speaker by flag, and applies nothing.

- [ ] **Step 1: Failing tests.** `AudioModelTests`: `aTapSendsThePlan` (live, USB chosen: last plan is that pin with `captureConfiguresAudio` false); `nothingChosenSendsOnlyTheDefaultPlan` (route changes and liveness flips: every plan equals `AudioPlan()`); `aRouteChangeDropsTheMissingSourceAndSaysSo`; `aRefusedPinFallsBackOnce` (the fake refuses: Automatic, the notice, exactly two plans); `aMonitorThatCannotStartTurnsOff`; `unpluggingHeadphonesStopsMonitoring`; `aNewChoiceClearsTheNotice`; `deviceChangesReachTheModel` (through `run()`, with `eventually`). `SimulatedAudioDeviceTests`: the two flags parse and leave `isScripted` false; the four routes.
- [ ] **Step 2: Implement,** run both suites and `LaunchConfigTests`.
- [ ] **Step 3: Commit.** `feat(audio): add the audio model, its device protocol and the simulated device`

### Task 3: The Audio section

**Files:** Create `OpenCam/UI/AudioSection.swift`, `OpenCam/UI/AudioLifecycle.swift`, `OpenCam/App/CameraModel+Audio.swift`. Modify: `OpenCam/App/NoticeSource.swift` (append `case audio` as the last case); `OpenCam/UI/VideoRecordRows.swift` (one line, `AudioSection(columns: verticalSizeClass == .compact ? 5 : 3)`, directly after the closing brace of `if let sweepCaption { … }`, now line 36; the recorder edits `:15-31`); `OpenCam/App/OpenCamApp.swift` (`@State private var audio: AudioModel?` after the `session` state; `_audio = State(initialValue: AudioModel(device: SimulatedAudioDevice(config: config)))` after `_session = State(initialValue: nil)`, and `_audio = State(initialValue: nil)` in the device branch; `.environment(audio)` and `.modifier(AudioLifecycle(model: model, audio: audio))` after `.environment(\.previewSource, …)`; the recorder edits `:35`). Test: `OpenCamTests/AudioNoticeTests.swift`.

**Interfaces. Consumes:** Tasks 1 and 2, `ChipRow`. **Produces:**

```swift
struct AudioSection: View { let columns: Int }       // reads @Environment(AudioModel.self) as an optional; draws nothing without one
struct AudioLifecycle: ViewModifier { let model: CameraModel?; let audio: AudioModel? }
extension CameraModel {
    var isAudioLive: Bool                             // AudioState.isLive(phase:mode:isInterrupted:)
    func showAudioNotice(_ text: String?)             // nil clears; never replaces a capture or configuration notice
}
```

Rules. The section is a heading "Audio" over two `ChipRow`s titled "Source" and "Monitor in headphones", fed from `audio.state`. `AudioLifecycle` runs `audio.run()` in a task, passes `model.isAudioLive` and `model.access.recordsSound` to `setCamera` on change (initial too), and passes `audio.notice` to `showAudioNotice`. The meters are untouched. Until Task 4 the phone has no audio model and shows no section.

- [ ] **Step 1: Failing tests.** `anAudioNoticeNeverCoversACaptureNotice`; `clearingRemovesOnlyTheAudioNotice`.
- [ ] **Step 2: Implement,** run the whole suite.
- [ ] **Step 3: Screenshots,** folded Simulator, with `SHOT_DIR=docs/screenshots/audio scripts/shot.sh <name> -mode video -screen record -cameraLook x …` (`-cameraLook` opens the sheet at its bottom, now the Audio section), in `-orientation portrait` and `landscape`: `audio-{v,h}-default` (Automatic selected, three Built-in chips, "On" dimmed with "Connect headphones to monitor."), `audio-{v,h}-wired` (`-wiredMic on -headphones on`: a Wired chip, "On" available), `audio-v-denied` (`-state micDenied`: both rows dimmed).
- [ ] **Step 4: Tap checks** on the `wired` launch, both orientations: tap Built-in Back (it is selected); tap Wired; tap Automatic; tap On; tap Off. On the `default` launch: tap the dimmed On (nothing changes). Check the Look row still shows above the section.
- [ ] **Step 5: Commit.** `feat(audio): add the Audio section to Record settings`

### Task 4: The device

**Files:** Create `OpenCam/Audio/CaptureAudioSession.swift`, `OpenCam/Audio/CameraSession+AudioSession.swift`, `OpenCam/Audio/SystemAudioDevice.swift`. Modify `OpenCam/App/OpenCamApp.swift` device branch only (line 48 becomes `let session = CameraSession()`, `_session = State(initialValue: session)`, `_audio = State(initialValue: AudioModel(device: SystemAudioDevice(capture: session)))`); `docs/device-checklist.md` (new section "4a. Audio source and monitoring" directly before "## 5. The open phone"; the recorder adds its section before "Things to decide").

**Interfaces. Consumes:** Tasks 1 and 2. **Produces:**

```swift
nonisolated protocol CaptureAudioSession: Sendable { func setConfiguresAudioSessionAutomatically(_ isAutomatic: Bool) async }
extension CameraSession: CaptureAudioSession { }     // sets session.automaticallyConfiguresApplicationAudioSession on the session's queue
actor SystemAudioDevice: AudioDevice { init(capture: any CaptureAudioSession) }
```

Isolation. The actor owns the engine (not Sendable, never leaves), the applied plan, the earlier buffer preference and the observer tokens. `AVAudioSession.sharedInstance()` and its ports are Sendable (H7) and are looked up by UID inside each call, never stored. Observers are registered on the first `route()` by a `nonisolated static` function, as `CameraSession.observeNotifications` (`CameraSession.swift:501-521`), with `queue: nil`: the blocks run on whatever thread posts, read nothing, and only yield into the `changes` continuation or start a `Task` on the actor. Tokens are removed in an `isolated deinit`.

Each step, its failure and its guard:

| Step | Calls | Guard and failure |
|---|---|---|
| `captureConfiguresAudio` | the capture flag (H1) | cannot fail |
| `pin` | find the port by UID in `availableInputs` (H5); `port.setPreferredDataSource` first, then `setPreferredInput` (H3, H4: one route change) | no port or no such data source throws `.inputMissing`; either setter throwing gives `.pinRefused`. The first take-over journals category, mode, options and input through `ErrorJournal.record` |
| `clearPin` | `setPreferredInput(nil)`, `setPreferredDataSource(nil)` | logged only |
| `startMonitor` | re-read the route and require `headphones != nil`; require category PlayAndRecord and `isInputAvailable`; keep `preferredIOBufferDuration`, set 0.005 s (H12, the latency setting); new `AVAudioEngine`; require non-zero rate and channels on the input node's output format and the output node's format (H9); `connectNode(input, to: mainMixerNode, format:)`; `start()` (H10) | any failed guard or throw gives `.monitorRefused`; the buffer call failing is logged only |
| `stopMonitor` | `stop()`, release the engine on the actor, restore the buffer preference | logged only |

Notifications: route change and available inputs change yield `.routeChanged`. Engine configuration change (H11): on the actor, if monitoring is applied, build a fresh engine and start again; a failure yields `.failed(.monitorRefused)`. Media services reset (H5): drop the engine, forget the applied plan, yield `.routeChanged`, so the next sync applies everything again.

What happens to an open monitor path:

| Event | Result |
|---|---|
| Interruption, backgrounding, Library, rescan, camera failure, photo mode | `isAudioLive` goes false: engine stopped, capture flag back to true, choice and preference kept, no notice. Live again: pin set again, monitor restarted |
| Recording start and stop | nothing; the engine keeps running |
| Headphones leave | engine stopped, preference off, "Headphones disconnected. Monitoring is off." |
| Chosen microphone leaves | Automatic, capture flag true, notice |

It cannot: remove Bluetooth delay, play through the speaker, or change the file (the engine only plays; nothing feeds the capture session).

- [ ] **Step 1: Implement.** No unit test: every decision is in `AudioState` and `AudioPlan.steps`; this file only executes steps.
- [ ] **Step 2: Whole suite, then the device SDK build,** 0 warnings.
- [ ] **Step 3: Checklist section 4a:**
  - After the first source choice, copy the journal line: category, mode, options.
  - Automatic, nothing touched: a clip sounds as it did on the previous build (channels, level).
  - Each source records: Built-in Front, Back, Bottom, a wired headset microphone, a USB microphone. Tap each microphone during a 10 s clip.
  - The source survives a recording start and stop, a lens switch, photo mode and back, the Library, backgrounding.
  - Unplug the chosen microphone: the row reads Automatic, the notice shows, the next clip has sound.
  - Back to Automatic by hand: note whether the next clip matches the first one at once or only after a lens switch.
  - Bluetooth: is a headset listed as a source; are Bluetooth headphones offered for monitoring. Note both.
  - Monitoring in wired headphones is heard with no noticeable delay; in Bluetooth with a delay.
  - A clip recorded with monitoring on has the sound once, clean, and the meters move.
  - Unplug headphones while monitoring and recording: nothing comes from the speaker, the notice shows, the clip keeps its sound.
  - A call or Siri stops monitoring and it returns afterwards.
  - Record start and stop haptics still fire with a source chosen and with monitoring on.
- [ ] **Step 4: Commit.** `feat(audio): drive the audio session and the headphone monitor on the device`

## Not in this plan

Gain, stereo and spatial modes, polar patterns, channel maps, speaker monitoring, meter changes, saving any audio choice, changing category options for Bluetooth, the system input picker (`AVInputPickerInteraction`, AVKit, iOS 26), monitoring fed from the recorder's audio data output.

## To confirm on the phone

Everything in section 4a. The headers do not state: the mode and options the capture session sets; whether an engine input may run beside the capture session's; whether the session picks its own microphone again as soon as the flag returns to true; whether a 5 ms buffer preference is honoured while recording.

## Rulings on the open questions (controller, 2026-11-12, overnight run)

1. **Bluetooth microphones and headphones may not be listed:** ship as planned and read the journal line on the phone; a follow-up changes the options only if they are missing.
2. **The section sits below the estimate line** tonight, to stay clear of the recorder's lines; it moves above the estimate after both branches are merged.
3. **If monitoring fails beside a recording on the phone:** only then feed a player node from the recorder's audio output.
4. **If a chosen source does not hold on the phone:** replace the Source row with the system's input picker.

The owner is asleep for this build. With Source on Automatic and monitoring off, which is how it starts, nothing here touches the audio session, so a recording sounds exactly as before.
