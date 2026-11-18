import AVFoundation
import OSLog

/// A scripted run of the real camera, reached only with the `-lensRun` launch argument. The app starts as always; this then
/// drives the model through the calls the buttons make (`selectLens`, the record selection, the shutter, the manual sliders,
/// the mode toggle), and after each one reads the camera itself to see which camera, lens and zoom it is on, and whether the
/// model raised the viewfinder blur. The report goes to `Documents/lens-run.json`; the session's own `[timing]` lines go to
/// `opencam-errors.log` as on any launch. The clips it records stay in the Library.
enum LensRun {
    static let fileName = "lens-run.json"

    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains("-lensRun") }

    static func run(model: CameraModel, session: CameraSession, progress: LensRunProgress) async {
        await LensRunner(model: model, session: session, progress: progress).run()
    }
}

/// What a step should do to the picture and which camera it should end on.
enum LensRunExpectation: String {
    /// No blur; the combined camera, locked to the lens the button names.
    case fast
    case blurToCombined = "blur to combined"
    case blurToOwn = "blur to own"
    /// No blur and no camera change: the session stays on the lens's own camera.
    case quietOnOwn = "no blur, stays on own"

    var wantsBlur: Bool { self == .blurToCombined || self == .blurToOwn }
    var wantsCombined: Bool { self == .fast || self == .blurToCombined }
}

final class LensRunner {
    private static let logger = Logger(subsystem: "local.opencam.app", category: "LensRun")
    private let model: CameraModel
    private let session: CameraSession
    private let progress: LensRunProgress
    private var report: LensRunReport

    init(model: CameraModel, session: CameraSession, progress: LensRunProgress) {
        self.model = model
        self.session = session
        self.progress = progress
        report = LensRunReport(takenAt: .now, buildConfiguration: Self.buildConfiguration, modelIdentifier: DeviceIdentity.modelIdentifier(),
                               osBuild: DeviceIdentity.osBuild(), thermalAtStart: Self.thermal)
    }

    func run() async {
        save()
        progress.line = "Lens run. Prop the phone facing the room. Starting in 10 seconds."
        try? await Task.sleep(for: .seconds(10))
        guard await waitUntil(seconds: 30, { self.model.phase == .ready }) else {
            note("run", "The camera never became ready", context: "phase: \(model.phase)")
            return finish()
        }
        report.combinedCamera = model.combinedCamera.map {
            "id \($0.deviceUniqueID), base zooms \($0.baseZoomByDeviceID.values.sorted()), \($0.formats.count) formats"
        } ?? "none"
        let lenses = model.capabilities.lenses
        guard let ultra = lenses.first(where: { $0.kind == .ultraWide && $0.zoomFactor == 1 }),
              let wide = lenses.first(where: { $0.kind == .wide && $0.zoomFactor == 1 }),
              let wide2 = lenses.first(where: { $0.kind == .wide && $0.zoomFactor == 2 }) else {
            note("run", "A back lens is missing", context: "lenses: \(lenses.map(\.id))")
            return finish()
        }
        let round = [ultra, wide, wide2, wide, ultra, wide2, ultra, wide]

        // Start from video, 1x, 4K 30 HEVC in Rec. 709, however the app came up.
        if model.mode != .video { await act("To video mode", expects: nil) { self.model.mode = .video } }
        if model.lensID != wide.id { await act("To 1x", expects: nil) { self.model.selectLens(wide.id) } }
        await format("4K 30 Rec. 709 HEVC", .hevc, "High", 3840, 2160, 30, .rec709, expects: nil)

        for lens in round { await tap(lens, in: "4K 30 Rec. 709", expects: .fast, settle: .milliseconds(1200)) }
        await format("4K 60 HLG HEVC", .hevc, "High", 3840, 2160, 60, .hlg, expects: .blurToCombined)
        for lens in round { await tap(lens, in: "4K 60 HLG", expects: .fast) }
        await format("1080p 30 Rec. 709 HEVC", .hevc, "High", 1920, 1080, 30, .rec709, expects: .blurToCombined)
        for lens in round { await tap(lens, in: "1080p 30 Rec. 709", expects: .fast) }

        // Clips on the system recorder, on the wide and on the ultra wide lens.
        await format("4K 30 Rec. 709 HEVC", .hevc, "High", 3840, 2160, 30, .rec709, expects: .blurToCombined)
        await recordClip("HEVC clip on 1x", seconds: 5, lens: wide, frameRate: 30)
        await tap(ultra, in: "4K 30 Rec. 709", expects: .fast)
        await recordClip("HEVC clip on 0.5x", seconds: 3, lens: ultra, frameRate: 30)
        await tap(wide, in: "4K 30 Rec. 709", expects: .fast)

        // A clip on the writer recorder.
        if await format("4K 30 HLG ProRes 422 Proxy", .proRes, "422 Proxy", 3840, 2160, 30, .hlg, expects: .blurToCombined) {
            await recordClip("ProRes clip on 1x", seconds: 3, lens: wide, frameRate: 30)
            for lens in [ultra, wide2, wide] { await tap(lens, in: "ProRes 4K 30 HLG", expects: .fast) }
        }
        await format("4K 30 Rec. 709 HEVC", .hevc, "High", 3840, 2160, 30, .rec709, expects: .blurToCombined)

        await manualSequence(wide: wide, ultra: ultra)

        // Above 60 fps the lenses keep their own cameras.
        if await format("1080p 120 Rec. 709 HEVC", .hevc, "High", 1920, 1080, 120, .rec709, expects: .blurToOwn) {
            await tap(ultra, in: "1080p 120", expects: .blurToOwn)
            await tap(wide, in: "1080p 120", expects: .blurToOwn)
        }
        await format("4K 30 Rec. 709 HEVC", .hevc, "High", 3840, 2160, 30, .rec709, expects: .blurToCombined)

        // Photo mode never uses the combined camera.
        await act("To photo mode", expects: .blurToOwn) { self.model.toggleMode() }
        await tap(ultra, in: "photo", expects: .blurToOwn)
        await tap(wide, in: "photo", expects: .blurToOwn)
        await act("Back to video mode", expects: .blurToCombined) { self.model.toggleMode() }

        // A front lens and back.
        if let front = lenses.first(where: { $0.kind == .outerUltraWide }) {
            await tap(front, in: "4K 30 Rec. 709", expects: .blurToOwn)
            await tap(wide, in: "4K 30 Rec. 709", expects: .blurToCombined)
        }

        await rapidTaps([ultra, wide, wide2])
        finish()
    }

    // MARK: Steps

    /// A lens button.
    private func tap(_ lens: Lens, in formatName: String, expects: LensRunExpectation, settle: Duration = .milliseconds(400)) async {
        let from = model.currentLens?.label ?? "?"
        await act("\(formatName): \(from) to \(lens.label)", expects: expects, settle: settle) { self.model.selectLens(lens.id) }
    }

    /// A record selection. Returns false, with a note and nothing changed, when the lens does not offer it.
    @discardableResult
    private func format(_ name: String, _ family: CodecFamily, _ quality: String, _ width: Int, _ height: Int, _ rate: Int, _ colour: ColourMode,
                        expects: LensRunExpectation?) async -> Bool {
        let selection = RecordSelection(family: family, quality: quality, resolution: .named(width: width, height: height), frameRate: rate, colour: colour)
        guard model.recordResolver.option(for: selection) != nil else {
            note("format", "The lens does not offer the format", context: "format: \(name), lens: \(model.lensID)")
            return false
        }
        guard model.record != selection else { return true }
        await act("Format: \(name)", expects: expects) { self.model.record = selection }
        return true
    }

    /// The manual shutter moves the session to the lens's own camera; returning it to Auto moves nothing; the next lens tap
    /// returns to the combined camera.
    private func manualSequence(wide: Lens, ultra: Lens) async {
        guard await waitUntil(seconds: 3, { self.model.scale(for: .shutter) != nil && self.model.canAdjustControls }),
              let shutter = model.scale(for: .shutter) else {
            note("manualSequence", "No shutter scale", context: "ranges: \(String(describing: model.manualRanges))")
            return
        }
        await act("Shutter by hand on 1x", expects: .blurToOwn, also: { state in
            if self.model.manual.exposure == .automatic { return "the model's exposure went back to automatic" }
            return state["exposure mode"] == "3" ? nil : "the camera's exposure mode is \(state["exposure mode"] ?? "?"), not custom (3)"
        }) { self.model.setControl(.shutter, step: shutter.values.count / 2) }

        if let temperature = model.scale(for: .temperature) {
            await act("White balance by hand", expects: .quietOnOwn, also: { _ in
                self.model.manual.whiteBalance == .automatic ? "the white balance was not taken" : nil
            }) { self.model.setControl(.temperature, step: temperature.values.count / 2) }
        }
        await act("Shutter back to Auto", expects: .quietOnOwn, also: { _ in
            self.model.manual.exposure == .automatic ? nil : "the model's exposure is still manual"
        }) { self.model.setAutomatic(.shutter) }

        await recordClip("HEVC clip on the wide camera itself, after Auto", seconds: 2, lens: wide, frameRate: 30, onCombined: false)
        await act("After that clip ended", expects: .quietOnOwn, also: { _ in
            self.model.manual.whiteBalance == .automatic ? "the white balance set by hand was reset" : nil
        }) {}

        await tap(ultra, in: "after manual", expects: .blurToCombined)
        await append("Controls after that tap", expects: "check", blur: false, since: .now, lensActiveMs: nil,
                     why: model.manual.isAutomatic ? nil : "a control is still set by hand")
        await tap(wide, in: "after manual", expects: .fast)
    }

    /// Twenty lens taps 60 ms apart, never waiting; the camera must end on the last one.
    private func rapidTaps(_ lenses: [Lens]) async {
        report.breadcrumb = "Rapid taps"
        save()
        progress.line = "Rapid taps"
        var blurSeen = false
        let start = ContinuousClock.now
        for index in 0..<20 {
            model.selectLens(lenses[index % lenses.count].id)
            blurSeen = blurSeen || model.isViewfinderChanging
            try? await Task.sleep(for: .milliseconds(60))
        }
        await observe("Rapid taps, 20 in a row, ending on \(model.currentLens?.label ?? "?")", expects: .fast, blur: blurSeen, since: start,
                      settle: .milliseconds(600), also: nil)
    }

    /// One clip through the shutter: the lens must not change by itself while it records, and the file must hold every frame.
    private func recordClip(_ label: String, seconds: Int, lens: Lens, frameRate: Int, onCombined: Bool = true) async {
        report.breadcrumb = label
        save()
        progress.line = label
        let before = model.lastCapture
        let start = ContinuousClock.now
        model.capturePressed()
        guard await waitUntil(seconds: 5, { self.model.isRecording && self.model.recordingStart != nil }) else {
            if model.isRecording { model.capturePressed() }
            await append(label, expects: "check", blur: false, since: start, lensActiveMs: nil, why: "the recording did not start")
            return
        }
        var lensesSeen: Set<String> = []
        var switchingSeen: Set<String> = []
        for _ in 0..<(seconds * 2) {
            try? await Task.sleep(for: .milliseconds(500))
            let state = await session.lensState()
            lensesSeen.insert(state["active lens id"] ?? state["camera id"] ?? "none")
            if let switching = state["switching active"] { switchingSeen.insert(switching) }
        }
        model.capturePressed()
        let blurAtStop = model.isViewfinderChanging
        let didStop = await waitUntil(seconds: 15) { !self.model.isRecording }
        let didSave = await waitUntil(seconds: 10) { self.model.lastCapture != nil && self.model.lastCapture != before }
        await model.waitForQueuedConfigures()

        var problems: [String] = []
        if !didStop { problems.append("the recording did not stop") }
        if blurAtStop || model.isViewfinderChanging { problems.append("the blur was raised at the stop") }
        if lensesSeen != [lens.deviceUniqueID] { problems.append("lenses seen while recording: \(lensesSeen.sorted())") }
        if onCombined, switchingSeen != ["locked"] { problems.append("switching while recording: \(switchingSeen.sorted())") }
        var clip = "not saved"
        if didSave, let url = model.lastCapture {
            do {
                let facts = try await ClipInspector.inspect(url: url, requestedFrameRate: frameRate)
                clip = "\(url.lastPathComponent): \(facts.codecFourCC) \(facts.width)x\(facts.height), \(facts.durationSeconds) s, \(facts.frameCount.map(String.init) ?? "?") frames, \(facts.droppedFrames.map(String.init) ?? "?") missing, \(facts.colour?.rawValue ?? "?"), dropped while recording \(model.droppedFrames)"
                if (facts.droppedFrames ?? 0) > 1 { problems.append("frames missing: \(facts.droppedFrames ?? 0)") }
            } catch {
                problems.append("the clip could not be read: \(error)")
            }
        } else {
            problems.append("no clip was saved")
        }
        await append("\(label) (\(clip))", expects: "check", blur: blurAtStop, since: start, lensActiveMs: nil,
                     why: problems.isEmpty ? nil : problems.joined(separator: "; "))
    }

    /// Runs `action`, notes the blur at once, waits for the model's configures, then watches the camera.
    private func act(_ label: String, expects: LensRunExpectation?, settle: Duration = .milliseconds(400),
                     also: (([String: String]) -> String?)? = nil, _ action: () -> Void) async {
        report.breadcrumb = label
        save()
        progress.line = label
        let start = ContinuousClock.now
        action()
        let blur = model.isViewfinderChanging
        await observe(label, expects: expects, blur: blur, since: start, settle: settle, also: also)
    }

    private func observe(_ label: String, expects: LensRunExpectation?, blur: Bool, since start: ContinuousClock.Instant, settle: Duration,
                         also: (([String: String]) -> String?)?) async {
        await model.waitForQueuedConfigures()
        let configureWaitMs = Self.milliseconds(since: start)
        guard let expects, let lens = model.currentLens else {
            try? await Task.sleep(for: settle)
            await append(label, expects: "check", blur: blur, since: start, lensActiveMs: nil, why: nil, configureWaitMs: configureWaitMs)
            return
        }
        let wanted = wantedState(for: lens, combined: expects.wantsCombined)
        var lensActiveMs: Double?
        for _ in 0..<300 {
            if mismatch(await session.lensState(), wanted) == nil {
                lensActiveMs = Self.milliseconds(since: start)
                break
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
        try? await Task.sleep(for: settle)
        let state = await session.lensState()
        var problems: [String] = []
        if blur != expects.wantsBlur { problems.append(expects.wantsBlur ? "no blur was raised" : "the blur was raised") }
        if let difference = mismatch(state, wanted) { problems.append(difference) }
        let combinedZoom = model.lastWorking?.configuration.combined?.zoomFactor
        if expects.wantsCombined != (combinedZoom != nil) {
            problems.append(expects.wantsCombined ? "the applied configuration is not on the combined camera" : "the applied configuration is on the combined camera")
        }
        if let notice = model.notice { problems.append("notice: \(notice)") }
        if let extra = also?(state) { problems.append(extra) }
        await append(label, expects: expects.rawValue, blur: blur, since: start, lensActiveMs: lensActiveMs,
                     why: problems.isEmpty ? nil : problems.joined(separator: "; "), configureWaitMs: configureWaitMs, state: state)
    }

    /// What the camera should report for `lens`: on the combined camera its id, the lens's own camera as the active lens, the
    /// lock and the lens's zoom there; else the lens's own camera at the lens's zoom.
    private func wantedState(for lens: Lens, combined: Bool) -> [String: String] {
        guard combined, let camera = model.combinedCamera, let base = camera.baseZoomByDeviceID[lens.deviceUniqueID] else {
            return ["camera id": lens.deviceUniqueID, "zoom": String(lens.zoomFactor)]
        }
        return ["camera id": camera.deviceUniqueID, "active lens id": lens.deviceUniqueID, "switching": "locked", "zoom": String(base * lens.zoomFactor)]
    }

    /// The first key on which `state` is not what is wanted, as text; nil when all match. Zooms match within 0.01.
    private func mismatch(_ state: [String: String], _ wanted: [String: String]) -> String? {
        for (key, value) in wanted.sorted(by: { $0.key < $1.key }) {
            let found = state[key] ?? "none"
            if key == "zoom", let a = Double(found), let b = Double(value), abs(a - b) < 0.01 { continue }
            if found != value { return "\(key) is \(found), wanted \(value)" }
        }
        return nil
    }

    private func append(_ label: String, expects: String, blur: Bool, since start: ContinuousClock.Instant, lensActiveMs: Double?, why: String?,
                        configureWaitMs: Double? = nil, state: [String: String]? = nil) async {
        let sessionState: [String: String]
        if let state {
            sessionState = state
        } else {
            sessionState = await session.lensState()
        }
        report.steps.append(LensRunStep(
            label: label, expects: expects, blurRaised: blur, configureWaitMs: configureWaitMs ?? Self.milliseconds(since: start),
            lensActiveMs: lensActiveMs, modelLens: model.currentLens?.label ?? "?",
            combinedZoom: model.lastWorking?.configuration.combined?.zoomFactor, session: sessionState, notice: model.notice,
            passed: why == nil, why: why))
        if let why { Self.logger.error("[LensRun:step] A step did not match — {step: \(label, privacy: .public), why: \(why, privacy: .public)}") }
        save()
    }

    // MARK: Plumbing

    private func finish() {
        report.passed = report.steps.filter(\.passed).count
        report.failed = report.steps.count - report.passed
        report.thermalAtEnd = Self.thermal
        report.breadcrumb = "finished"
        report.isComplete = true
        save()
        progress.line = "Lens run finished: \(report.passed) of \(report.steps.count) steps as expected."
        progress.isFinished = true
    }

    private func note(_ function: String, _ description: String, context: String) {
        let text = "[LensRun:\(function)] \(description) — {\(context)}"
        Self.logger.error("\(text, privacy: .public)")
        report.errors.append(text)
        save()
    }

    private func waitUntil(seconds: Int, _ condition: () -> Bool) async -> Bool {
        for _ in 0..<(seconds * 50) {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    /// A report that could not be written is logged; the run goes on.
    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let directory = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            try encoder.encode(report).write(to: directory.appending(path: LensRun.fileName), options: .atomic)
        } catch {
            Self.logger.error("[LensRun:save] The report could not be written — {reason: \(error.localizedDescription, privacy: .public)}")
        }
    }

    private static func milliseconds(since start: ContinuousClock.Instant) -> Double {
        let (seconds, attoseconds) = (ContinuousClock.now - start).components
        return (Double(seconds) * 1000 + Double(attoseconds) / 1e15).rounded()
    }

    private static var thermal: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }

    private static var buildConfiguration: String {
        #if DEBUG
        "Debug"
        #else
        "Release"
        #endif
    }
}

extension CameraSession {
    /// The attached camera as the lens run reports it. Reads only.
    func lensState() -> [String: String] {
        guard let device = videoInput?.device else { return ["camera id": "none"] }
        var state: [String: String] = [
            "camera id": device.uniqueID,
            "camera": device.localizedName,
            "zoom": String(Double(device.videoZoomFactor)),
            "zoom minimum": String(Double(device.minAvailableVideoZoomFactor)),
            "exposure mode": String(device.exposureMode.rawValue),
            "white balance mode": String(device.whiteBalanceMode.rawValue),
            "focus mode": String(device.focusMode.rawValue),
            "running": String(session.isRunning),
        ]
        if device.isVirtualDevice {
            state["active lens id"] = device.activePrimaryConstituent?.uniqueID ?? "none"
            state["active lens"] = device.activePrimaryConstituent?.localizedName ?? "none"
            state["switching"] = Self.name(device.primaryConstituentDeviceSwitchingBehavior)
            state["switching active"] = Self.name(device.activePrimaryConstituentDeviceSwitchingBehavior)
        }
        if session.outputs.contains(recorder.output) {
            state["movie output's own switching rule"] = String(recorder.output.isPrimaryConstituentDeviceSwitchingBehaviorForRecordingEnabled)
        }
        return state
    }

    private static func name(_ behaviour: AVCaptureDevice.PrimaryConstituentDeviceSwitchingBehavior) -> String {
        switch behaviour {
        case .unsupported: "unsupported"
        case .auto: "auto"
        case .restricted: "restricted"
        case .locked: "locked"
        @unknown default: "unknown \(behaviour.rawValue)"
        }
    }
}
