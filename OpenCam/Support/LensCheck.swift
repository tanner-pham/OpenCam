import AVFoundation
import OSLog
import Synchronization

/// A one-off diagnostic, reached only with the `-lensCheck` launch argument. It asks the phone, with the cameras to itself,
/// whether the back lens buttons could change lens on the combined back camera ("Back Dual Wide Camera") by zoom instead of
/// by swapping the camera input: how long a lens change takes there, whether manual exposure, white balance and focus survive
/// it, whether the writer path's 10-bit data output and the movie output run on it, and whether it offers Bayer RAW photos.
/// The report goes to `Documents/lens-check.json`. `-lensCheckOnly switch,manual` runs only the named sections
/// (facts, switch, manual, movie, photo, baseline, close).
nonisolated enum LensCheck {
    static let fileName = "lens-check.json"

    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains("-lensCheck") }

    private static var only: Set<String>? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-lensCheckOnly"), index + 1 < arguments.count else { return nil }
        return Set(arguments[index + 1].split(separator: ",").map(String.init))
    }

    /// Runs off the main actor: starting a session blocks.
    @concurrent static func runAndWrite(progress: LensCheckProgress) async {
        await LensCheckRunner(progress: progress, only: only).run()
    }

    /// On the combined camera zoom 1 is the ultra wide lens, which the lens buttons call 0.5x.
    static func label(_ zoom: CGFloat) -> String {
        "zoom \(Double(zoom)) (\(Double(zoom) / 2)x)"
    }
}

/// The three back cameras the check uses.
nonisolated struct LensCheckCameras {
    let dual: AVCaptureDevice
    let wide: AVCaptureDevice
    let ultra: AVCaptureDevice
}

/// Runs the sections in order and keeps the report. Used from one task.
nonisolated final class LensCheckRunner {
    private static let logger = Logger(subsystem: "local.opencam.app", category: "LensCheck")
    private let progress: LensCheckProgress
    private let only: Set<String>?
    private var report: LensCheckReport

    init(progress: LensCheckProgress, only: Set<String>?) {
        self.progress = progress
        self.only = only
        report = LensCheckReport(takenAt: .now, buildConfiguration: Self.buildConfiguration, modelIdentifier: DeviceIdentity.modelIdentifier(),
                                 osBuild: DeviceIdentity.osBuild(), thermalAtStart: Self.thermal, notes: Self.notes)
    }

    func run() async {
        save()
        guard await hasCameraAccess() else {
            note("run", "No camera access", context: "status: \(AVCaptureDevice.authorizationStatus(for: .video).rawValue)")
            await finish()
            return
        }
        guard let dual = Self.camera(.builtInDualWideCamera), let wide = Self.camera(.builtInWideAngleCamera), let ultra = Self.camera(.builtInUltraWideCamera) else {
            note("run", "A back camera is missing", context: "dual wide: \(Self.camera(.builtInDualWideCamera) != nil), wide: \(Self.camera(.builtInWideAngleCamera) != nil), ultra wide: \(Self.camera(.builtInUltraWideCamera) != nil)")
            await finish()
            return
        }
        let cameras = LensCheckCameras(dual: dual, wide: wide, ultra: ultra)
        await progress.set(headline: "Aim the back cameras at the room. Nothing closer than a metre.", line: "Starting in 5 seconds")
        try? await Task.sleep(for: .seconds(5))
        await section("facts", "Reading the cameras") { self.collectFacts(cameras) }
        await section("switch", "Lens changes") { await self.runSwitching(cameras) }
        await section("manual", "Manual controls across a lens change") { await self.runManual(cameras) }
        await section("movie", "Movie output") { await self.runMovie(cameras) }
        await section("photo", "Photo preset") { await self.runPhoto(cameras) }
        await section("baseline", "Today's lens change") { await self.runBaseline(cameras) }
        await section("close", "Close subject") { await self.runCloseSubject(cameras) }
        await finish()
    }

    // MARK: Sections

    private func collectFacts(_ cameras: LensCheckCameras) {
        let dual = cameras.dual
        var facts: [String: String] = [:]
        facts["dual wide: lenses"] = dual.constituentDevices.map { LensCheckRig.name($0) }.joined(separator: ", ")
        facts["dual wide: switch-over zoom factors"] = dual.virtualDeviceSwitchOverVideoZoomFactors.map { "\($0)" }.joined(separator: " ")
        facts["dual wide: switching behaviour"] = LensCheckRig.name(dual.primaryConstituentDeviceSwitchingBehavior)
        facts["dual wide: restricted conditions"] = String(dual.primaryConstituentDeviceRestrictedSwitchingBehaviorConditions.rawValue)
        facts["dual wide: can lock to a lens"] = String(dual.isPrimaryConstituentDeviceSwitchingBehaviorLockedWithDeviceSupported)
        facts["dual wide: fallback lenses supported"] = dual.supportedFallbackPrimaryConstituentDevices.map { LensCheckRig.name($0) }.joined(separator: ", ")
        facts["dual wide: fallback lenses"] = dual.fallbackPrimaryConstituentDevices.map { LensCheckRig.name($0) }.joined(separator: ", ")
        for (name, device) in [("dual wide", dual), ("wide", cameras.wide), ("ultra wide", cameras.ultra)] {
            facts["\(name): name"] = device.localizedName
            facts["\(name): formats"] = String(device.formats.count)
            facts["\(name): zoom range available"] = "\(device.minAvailableVideoZoomFactor)...\(device.maxAvailableVideoZoomFactor)"
            facts["\(name): display zoom multiplier"] = String(Double(device.displayVideoZoomFactorMultiplier))
            facts["\(name): minimum focus distance mm"] = String(device.minimumFocusDistance)
            facts["\(name): geometric distortion correction"] = "supported \(device.isGeometricDistortionCorrectionSupported), on \(device.isGeometricDistortionCorrectionSupported && device.isGeometricDistortionCorrectionEnabled)"
            for (key, value) in LensCheckRig.manualState(of: device, prefix: "\(name): ") where key.contains("supports") || key.contains("aperture") {
                facts[key] = value
            }
        }
        report.facts = facts
    }

    /// Lens changes on the combined camera with the writer path's data output. The first format gets every method; the others
    /// one round of jumps and one of locks.
    private func runSwitching(_ cameras: LensCheckCameras) async {
        for (number, format) in [LensCheckFormat.uhd30HLG, .uhd60HLG, .hd30SDR].enumerated() {
            await step("Lens changes, \(format.label)")
            let index = report.switching.count
            report.switching.append(LensCheckRun(label: format.label))
            let failure = await withRig(cameras.dual, .frames, format) { rig throws(LensCheckFailure) in
                self.report.switching[index].setup = rig.setup
                try await self.switchTrials(rig, cameras, index: index, isFull: number == 0)
            }
            report.switching[index].failure = failure
            save()
        }
    }

    private func switchTrials(_ rig: LensCheckRig, _ cameras: LensCheckCameras, index: Int, isFull: Bool) async throws(LensCheckFailure) {
        let label = report.switching[index].label
        let everyLens: [CGFloat] = [2, 1, 2, 4, 2, 1, 4, 1]
        // Auto: the camera picks the lens for the zoom.
        try rig.setBehaviour(.auto)
        try rig.jump(to: 1)
        try? await Task.sleep(for: .milliseconds(800))
        for round in 1...(isFull ? 3 : 1) {
            await step("Lens changes, \(label): zoom jumps, round \(round)")
            await cycle(rig, \.switching, index, method: "auto jump", targets: everyLens) { zoom throws(LensCheckFailure) in
                try rig.jump(to: zoom)
            }
        }
        if isFull {
            for rate: Float in [4, 16] {
                for round in 1...2 {
                    await step("Lens changes, \(label): zoom ramps at \(Int(rate)), round \(round)")
                    await cycle(rig, \.switching, index, method: "auto ramp \(Int(rate))", targets: [2, 1, 4, 1], settle: .milliseconds(700 + Int(2000 / rate))) { zoom throws(LensCheckFailure) in
                        try rig.ramp(to: zoom, rate: rate)
                        return nil
                    }
                }
            }
            // Restricted with no condition: no fallback lens, lens changes only for the zoom.
            try rig.setBehaviour(.restricted)
            for round in 1...2 {
                await step("Lens changes, \(label): restricted, round \(round)")
                await cycle(rig, \.switching, index, method: "restricted jump", targets: [2, 1, 4, 1], settle: .milliseconds(1200)) { zoom throws(LensCheckFailure) in
                    try rig.jump(to: zoom)
                }
            }
            try rig.setBehaviour(.auto)
        }
        guard rig.canLockToLens else { return }
        // Locked: each lens button names its lens.
        await step("Lens changes, \(label): first lens lock")
        _ = try rig.lock(to: cameras.ultra, zoom: 1)
        try? await Task.sleep(for: .milliseconds(800))
        for round in 1...(isFull ? 3 : 1) {
            await step("Lens changes, \(label): lens locks, round \(round)")
            await cycle(rig, \.switching, index, method: "locked", targets: everyLens) { zoom throws(LensCheckFailure) in
                try rig.lock(to: zoom >= 2 ? cameras.wide : cameras.ultra, zoom: zoom)
            }
        }
        try rig.setBehaviour(.auto)
    }

    private func runManual(_ cameras: LensCheckCameras) async {
        let failure = await withRig(cameras.dual, .frames, .uhd30HLG) { rig throws(LensCheckFailure) in
            for mode in rig.canLockToLens ? ["auto", "locked"] : ["auto"] {
                try await self.manualTrials(rig, cameras, mode: mode)
            }
        }
        if let failure { note("runManual", "The manual trials stopped", context: "reason: \(failure)") }
    }

    /// Each control alone, set on the ultra wide lens and carried to the wide lens and back; then all three, set on the wide lens.
    /// `mode` is how the lens is changed: "auto" by zoom, "locked" by locking to the lens.
    private func manualTrials(_ rig: LensCheckRig, _ cameras: LensCheckCameras, mode: String) async throws(LensCheckFailure) {
        func go(_ lens: AVCaptureDevice) throws(LensCheckFailure) {
            let zoom: CGFloat = lens.uniqueID == cameras.ultra.uniqueID ? 1 : 2
            if mode == "locked" {
                _ = try rig.lock(to: lens, zoom: zoom)
            } else {
                try rig.jump(to: zoom)
            }
        }
        func read(_ label: String, refusal: String? = nil) async {
            try? await Task.sleep(for: .milliseconds(900))
            var values = rig.state()
            if let refusal { values["refused"] = refusal }
            report.manual.append(LensCheckReading(label: "\(mode): \(label)", values: values))
            save()
        }
        try rig.setBehaviour(.auto)
        try rig.resetManual()
        try go(cameras.ultra)
        await read("ultra wide, all automatic")
        try go(cameras.wide)
        await read("wide, all automatic")
        let controls: [(String, () throws(LensCheckFailure) -> String?)] = [
            ("custom exposure", rig.setCustomExposure), ("locked white balance", rig.setLockedWhiteBalance), ("locked focus", rig.setLockedFocus),
        ]
        for (name, set) in controls {
            await step("Manual controls, \(mode): \(name)")
            try go(cameras.ultra)
            try? await Task.sleep(for: .milliseconds(900))
            let refusal = try set()
            await read("\(name) set on ultra wide", refusal: refusal)
            if refusal == nil {
                try go(cameras.wide)
                await read("\(name), after changing to wide")
                try go(cameras.ultra)
                await read("\(name), back on ultra wide")
            }
            try rig.resetManual()
        }
        await step("Manual controls, \(mode): all three")
        try go(cameras.wide)
        try? await Task.sleep(for: .milliseconds(900))
        let refusals = [try rig.setCustomExposure(), try rig.setLockedWhiteBalance(), try rig.setLockedFocus()].compactMap { $0 }
        await read("all three set on wide", refusal: refusals.isEmpty ? nil : refusals.joined(separator: "; "))
        try go(cameras.ultra)
        await read("all three, after changing to ultra wide")
        try go(cameras.wide)
        await read("all three, back on wide")
        try rig.resetManual()
        try rig.setBehaviour(.auto)
    }

    /// The system movie output on the combined camera, recording across lens changes: once with lens locks and the output's
    /// own switching rule for recordings turned off, once with zoom jumps and every default.
    private func runMovie(_ cameras: LensCheckCameras) async {
        let trials: [(String, LensCheckFormat, Bool)] = [
            ("4K 30 HLG, lens locks, the recording's own switching rule off", .uhd30HLG, true),
            ("4K 60 HLG, zoom jumps, defaults", .uhd60HLG, false),
        ]
        for (label, format, wantsLock) in trials {
            await step("Movie output, \(label)")
            let index = report.movie.count
            report.movie.append(LensCheckRun(label: label))
            let failure = await withRig(cameras.dual, .movie, format) { rig throws(LensCheckFailure) in
                try await self.movieTrial(rig, cameras, index: index, format: format, usesLock: wantsLock && rig.canLockToLens)
            }
            report.movie[index].failure = failure
            save()
        }
    }

    private func movieTrial(_ rig: LensCheckRig, _ cameras: LensCheckCameras, index: Int, format: LensCheckFormat, usesLock: Bool) async throws(LensCheckFailure) {
        let output = rig.movieOutput
        var setup = rig.setup
        setup["movie: recording's switching rule on by default"] = String(output.isPrimaryConstituentDeviceSwitchingBehaviorForRecordingEnabled)
        setup["movie: recording's switching behaviour"] = LensCheckRig.name(output.primaryConstituentDeviceSwitchingBehaviorForRecording)
        setup["movie: recording's restricted conditions"] = String(output.primaryConstituentDeviceRestrictedSwitchingBehaviorConditionsForRecording.rawValue)
        setup["movie: codecs"] = output.availableVideoCodecTypes.map(\.rawValue).joined(separator: " ")
        setup["uses lens locks"] = String(usesLock)
        guard let connection = output.connection(with: .video), connection.isActive else {
            throw LensCheckFailure(message: "The movie output has no active video connection")
        }
        // An invalid settings dictionary raises an exception (AVCaptureFileOutput.h), so both are checked first, as `MovieRecorder` does.
        if output.availableVideoCodecTypes.contains(.hevc), output.supportedOutputSettingsKeys(for: connection).contains(AVVideoCodecKey) {
            output.setOutputSettings([AVVideoCodecKey: AVVideoCodecType.hevc], for: connection)
        }
        if usesLock {
            output.isPrimaryConstituentDeviceSwitchingBehaviorForRecordingEnabled = false
            _ = try rig.lock(to: cameras.ultra, zoom: 1)
        } else {
            try rig.setBehaviour(.auto)
            try rig.jump(to: 1)
        }
        report.movie[index].setup = setup
        try? await Task.sleep(for: .milliseconds(800))
        let url = FileManager.default.temporaryDirectory.appending(path: "lens-check-\(index).mov")
        try? FileManager.default.removeItem(at: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let delegate = LensCheckMovieDelegate()
        output.startRecording(to: url, recordingDelegate: delegate)
        try? await Task.sleep(for: .seconds(1))
        var file = ["switching behaviour active while recording": LensCheckRig.name(rig.device.activePrimaryConstituentDeviceSwitchingBehavior)]
        await cycle(rig, \.movie, index, method: usesLock ? "locked, recording" : "auto jump, recording", targets: [2, 1, 4, 1], settle: .milliseconds(900)) { zoom throws(LensCheckFailure) in
            if usesLock { return try rig.lock(to: zoom >= 2 ? cameras.wide : cameras.ultra, zoom: zoom) }
            return try rig.jump(to: zoom)
        }
        output.stopRecording()
        for _ in 0..<100 where !delegate.isFinished {
            try? await Task.sleep(for: .milliseconds(100))
        }
        file["finished"] = String(delegate.isFinished)
        if let error = delegate.errorText { file["error"] = error }
        do {
            let facts = try await ClipInspector.inspect(url: url, requestedFrameRate: format.framesPerSecond)
            file["codec"] = facts.codecFourCC
            file["size"] = "\(facts.width)x\(facts.height)"
            file["seconds"] = String(facts.durationSeconds)
            file["frames"] = facts.frameCount.map(String.init) ?? "unknown"
            file["frames missing for the duration"] = facts.droppedFrames.map(String.init) ?? "unknown"
            file["colour"] = facts.colour?.rawValue ?? "unknown"
            file["megabits per second"] = String(facts.megabitsPerSecond)
        } catch {
            file["read back failed"] = String(describing: error)
        }
        report.movie[index].file = file
    }

    /// What the photo output offers on the photo preset, on the combined camera and, as the control, on the wide camera,
    /// where the app's photo mode gets Bayer RAW today.
    private func runPhoto(_ cameras: LensCheckCameras) async {
        for (name, device) in [("dual wide", cameras.dual), ("wide camera (control)", cameras.wide)] {
            await step("Photo preset, \(name)")
            let failure = await withRig(device, .photo, nil) { rig throws(LensCheckFailure) in
                func read(_ label: String) async {
                    try? await Task.sleep(for: .milliseconds(700))
                    self.report.photoPreset.append(LensCheckReading(label: "\(name): \(label)", values: rig.photoFacts()))
                    self.save()
                }
                await read("as the preset leaves it")
                guard rig.isVirtual else { return }
                try rig.jump(to: 2)
                await read("auto, zoom 2 (1x)")
                guard rig.canLockToLens else { return }
                _ = try rig.lock(to: cameras.ultra, zoom: 1)
                await read("locked to ultra wide")
                _ = try rig.lock(to: cameras.wide, zoom: 2)
                await read("locked to wide")
                try rig.setBehaviour(.auto)
            }
            if let failure { note("runPhoto", "The photo preset check stopped", context: "camera: \(name), reason: \(failure)") }
        }
    }

    /// Today's lens change in the same session and with the same output: the wide camera's input swapped for the ultra wide's and back.
    private func runBaseline(_ cameras: LensCheckCameras) async {
        for format in [LensCheckFormat.uhd30HLG, .hd30SDR] {
            await step("Today's lens change, \(format.label)")
            let index = report.baseline.count
            report.baseline.append(LensCheckRun(label: format.label))
            let failure = await withRig(cameras.wide, .frames, format) { rig throws(LensCheckFailure) in
                self.report.baseline[index].setup = rig.setup
                for _ in 0..<3 {
                    for target in [cameras.ultra, cameras.wide] {
                        let transition = await rig.measure(method: "input swap", to: "\(LensCheckRig.name(target)) camera", settle: .milliseconds(1200)) { () throws(LensCheckFailure) in
                            try rig.swapInput(to: target)
                            return nil
                        }
                        self.report.baseline[index].transitions.append(transition)
                    }
                }
            }
            report.baseline[index].failure = failure
            save()
        }
    }

    /// With a subject closer than the wide lens can focus, which lens does 1x (zoom 2) get under each switching rule?
    private func runCloseSubject(_ cameras: LensCheckCameras) async {
        await progress.set(headline: "Now hold the back cameras about 5 cm from a surface and keep them there.", line: "Starting in 6 seconds")
        try? await Task.sleep(for: .seconds(6))
        let failure = await withRig(cameras.dual, .frames, .hd30SDR) { rig throws(LensCheckFailure) in
            func read(_ label: String) async {
                await self.step("Close subject: \(label)")
                try? await Task.sleep(for: .seconds(2))
                self.report.closeSubject.append(LensCheckReading(label: label, values: rig.state()))
                self.save()
            }
            try rig.setBehaviour(.auto)
            try rig.jump(to: 1)
            try? await Task.sleep(for: .seconds(1))
            try rig.jump(to: 2)
            await read("auto, zoom 2 (1x)")
            try rig.jump(to: 1)
            await self.step("Close subject: setting no fallback lens")
            try rig.setFallbackLenses([])
            try? await Task.sleep(for: .seconds(1))
            try rig.jump(to: 2)
            await read("auto with no fallback lens, zoom 2 (1x)")
            try rig.jump(to: 1)
            try rig.setFallbackLenses(nil)
            try rig.setBehaviour(.restricted)
            try? await Task.sleep(for: .seconds(1))
            try rig.jump(to: 2)
            await read("restricted, zoom 2 (1x)")
            try rig.setBehaviour(.auto)
            guard rig.canLockToLens else { return }
            _ = try rig.lock(to: cameras.wide, zoom: 2)
            await read("locked to wide")
            try rig.setBehaviour(.auto)
        }
        if let failure { note("runCloseSubject", "The close subject check stopped", context: "reason: \(failure)") }
        await progress.set(headline: "You can put the phone down.", line: "")
    }

    // MARK: Plumbing

    /// One section, unless `-lensCheckOnly` left it out or the phone is hot.
    private func section(_ key: String, _ title: String, _ body: () async -> Void) async {
        guard only?.contains(key) ?? true else { return }
        let heat = ProcessInfo.processInfo.thermalState
        guard heat != .serious, heat != .critical else {
            note("section", "Skipped because the phone is hot", context: "section: \(key), thermal: \(Self.thermal)")
            return
        }
        await step(title)
        await body()
        report.completedSections.append(key)
        save()
    }

    /// Names the step on screen and in the report before it starts, so a crash leaves its name on disk.
    private func step(_ text: String) async {
        report.breadcrumb = text
        save()
        await progress.set(line: text)
    }

    /// Builds a session, shows its preview, starts it, runs `body`, and stops it. Returns why it stopped early, if it did.
    private func withRig(_ device: AVCaptureDevice, _ outputs: LensCheckRig.Outputs, _ format: LensCheckFormat?,
                         _ body: (LensCheckRig) async throws(LensCheckFailure) -> Void) async -> String? {
        var rig: LensCheckRig?
        var failure: String?
        do throws(LensCheckFailure) {
            let made = try LensCheckRig(device: device, outputs: outputs, format: format)
            rig = made
            await progress.show(LensCheckSessionBox(session: made.session))
            try await made.start()
            try await body(made)
        } catch {
            failure = error.message
            note("withRig", "A session's trials stopped", context: "camera: \(device.localizedName), format: \(format?.label ?? "photo preset"), step: \(report.breadcrumb), reason: \(error.message)")
        }
        await progress.show(nil)
        rig?.stop()
        try? await Task.sleep(for: .milliseconds(400))
        return failure
    }

    /// Measures a change to each target zoom in turn and appends them to the run at `index` of `list`.
    private func cycle(_ rig: LensCheckRig, _ list: WritableKeyPath<LensCheckReport, [LensCheckRun]>, _ index: Int, method: String, targets: [CGFloat],
                       settle: Duration = .milliseconds(600), _ change: (CGFloat) throws(LensCheckFailure) -> Double?) async {
        for target in targets {
            let transition = await rig.measure(method: method, to: LensCheck.label(target), settle: settle) { () throws(LensCheckFailure) in try change(target) }
            report[keyPath: list][index].transitions.append(transition)
        }
        save()
    }

    private func finish() async {
        report.thermalAtEnd = Self.thermal
        report.breadcrumb = "finished"
        report.isComplete = true
        save()
        await progress.finish()
    }

    private func note(_ function: String, _ description: String, context: String) {
        let text = "[LensCheck:\(function)] \(description) — {\(context)}"
        Self.logger.error("\(text, privacy: .public)")
        report.errors.append(text)
    }

    /// A report that could not be written is logged; the run goes on.
    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
            let directory = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            try encoder.encode(report).write(to: directory.appending(path: LensCheck.fileName), options: .atomic)
        } catch {
            Self.logger.error("[LensCheck:save] The report could not be written — {reason: \(error.localizedDescription, privacy: .public)}")
        }
    }

    private func hasCameraAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: .video)
        default: false
        }
    }

    private static func camera(_ type: AVCaptureDevice.DeviceType) -> AVCaptureDevice? {
        AVCaptureDevice.DiscoverySession(deviceTypes: [type], mediaType: .video, position: .back).devices.first
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

    private static let notes = [
        "On the combined camera zoom 1 is the ultra wide lens (the 0.5x button), zoom 2 the wide lens (1x), zoom 4 the wide lens cropped (2x).",
        "Every time in a transition is in milliseconds from the moment just before the call that asked for the change.",
        "A frame's lens is read from its aperture (the {Exif} FNumber attached to each frame): f/2.2 is the ultra wide lens, f/1.6 the wide. firstOtherLensFrameCapturedMs is that frame's timestamp, firstOtherLensFrameArrivedMs when the app received it.",
        "lensChangeReportedMs is when the camera's activePrimaryConstituentDevice changed (key-value observation), which is separate from the frames.",
        "longestFrameGapMs is the longest time between two frames in a row from the last frame before the call onward. Near nominalFrameMs means no frame was missed; today's input swap shows a long gap here.",
        "Methods: 'auto jump' sets videoZoomFactor with the default switching behaviour; 'auto ramp N' ramps at N doublings a second; 'restricted jump' is the restricted behaviour with no fallback condition; 'locked' locks the camera to the lens the button names (new in iOS 27) and sets the zoom; 'input swap' is what the app does today.",
        "The switching and baseline sessions carry what the writer path carries: one full-size video data output with late frames kept, 10-bit x420 for HLG, and a preview layer. No sound, no asset writer.",
        "The movie sessions carry the movie output, a preview-sized data output as a look would add, and a preview layer. No sound.",
        "Manual readings list the combined camera's values and, under 'active lens:', the values of the lens it is using. Exposure mode 3 is custom, 2 continuous; white balance mode 0 is locked, 2 continuous; focus mode 0 is locked, 2 continuous.",
        "The close subject readings mean something only if the cameras were held a few centimetres from a surface.",
    ]
}

nonisolated extension LensCheckRig {
    /// Runs `change` and reports what the frames and the camera did around it. `change` returns how long a zoom waited for the
    /// camera's zoom range, when it had to.
    func measure(method: String, to: String, settle: Duration, _ change: () throws(LensCheckFailure) -> Double?) async -> LensCheckTransition {
        tap.reset()
        try? await Task.sleep(for: .milliseconds(200))
        let from = isVirtual ? LensCheck.label(device.videoZoomFactor) : "\(lensName) camera"
        let lensBefore = lensName
        let clock = session.synchronizationClock ?? CMClockGetHostTimeClock()
        let callHost = LensCheckTap.hostNow()
        let callSync = CMClockGetTime(clock).seconds
        var failure: String?
        var zoomWait: Double?
        do throws(LensCheckFailure) {
            zoomWait = try change()
        } catch {
            failure = error.message
        }
        let callMs = (LensCheckTap.hostNow() - callHost) * 1000
        try? await Task.sleep(for: settle)
        let window = tap.take()

        let before = window.frames.last { $0.arrived < callHost }
        let later = window.frames.filter { $0.arrived >= callHost }
        let other = before?.aperture.flatMap { was in
            later.first { frame in frame.aperture.map { abs($0 - was) > 0.05 } ?? false }
        }
        var longestGap = 0.0
        var previous = before?.captured
        for frame in later {
            if let previous { longestGap = max(longestGap, frame.captured - previous) }
            previous = frame.captured
        }
        let reported = window.lensChanges.first { $0.at >= callHost }
        let round = { (value: Double) in (value * 100).rounded() / 100 }
        return LensCheckTransition(
            method: method, from: from, to: to, lensBefore: lensBefore, lensAfter: lensName, zoomAfter: Double(device.videoZoomFactor),
            callMs: round(callMs), zoomWaitMs: zoomWait.map(round),
            lensChangeReportedMs: reported.map { round(($0.at - callHost) * 1000) }, lensChangeReportedTo: reported?.lens,
            firstOtherLensFrameCapturedMs: other.map { round(($0.captured - callSync) * 1000) },
            firstOtherLensFrameArrivedMs: other.map { round(($0.arrived - callHost) * 1000) },
            rampEndedMs: window.rampEnds.first { $0 >= callHost }.map { round(($0 - callHost) * 1000) },
            apertureBefore: before?.aperture, apertureAfter: window.frames.last?.aperture,
            nominalFrameMs: round(device.activeVideoMinFrameDuration.seconds * 1000), longestFrameGapMs: round(longestGap * 1000),
            framesAfterCall: later.count, framesDropped: window.dropped, dropReasons: window.dropReasons, failure: failure,
            frames: window.frames.map { frame in
                [round((frame.captured - callSync) * 1000), round((frame.arrived - callHost) * 1000), frame.aperture ?? -1,
                 frame.exposureSeconds.map { round($0 * 1000) } ?? -1, frame.iso ?? -1, frame.digitalZoom ?? -1]
            })
    }
}

/// Knows when the movie output finished its file, and with what error.
nonisolated final class LensCheckMovieDelegate: NSObject, AVCaptureFileOutputRecordingDelegate, Sendable {
    private let state = Mutex<(isFinished: Bool, error: String?)>((false, nil))

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: (any Error)?) {
        state.withLock { $0 = (true, error.map { String(describing: $0) }) }
    }

    var isFinished: Bool { state.withLock { $0.isFinished } }
    var errorText: String? { state.withLock { $0.error } }
}
