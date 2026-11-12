import Foundation
import Testing
@testable import OpenCam

/// Prints what the camera asks of the main actor with the phone's real capability list (6,192 video options), so a
/// freeze can be traced to a number. Bounds are generous on purpose: these tests report, they do not race.
@MainActor @Suite(.serialized) struct MainThreadCostTests {
    private static let wide = "com.apple.avfoundation.avcapturedevice.built-in_video:0"
    private static let ultraWide = "com.apple.avfoundation.avcapturedevice.built-in_video:5"
    private static let bound = Duration.seconds(5)

    private func readyModel(mode: CaptureMode = .video) throws -> CameraModel {
        // The phone's list with the writer options merged in (2,160 more options), as the Simulator and a shipped writer see it.
        let model = CameraModel(config: LaunchConfig(), capabilities: try Fixture.loadDuo().withWriterOptions(.all), isSimulator: true,
                                defaults: try Fixture.freshDefaults())
        model.phase = .ready
        model.mode = mode
        return model
    }

    @Test func writerOptionsDerivation() throws {
        let capabilities = try Fixture.loadDuo()
        #expect(PerfClock.report("withWriterOptions on the phone's list", runs: 5) { _ = capabilities.withWriterOptions(.all) } < Self.bound)
    }

    @Test func launchCosts() throws {
        let capabilities = try Fixture.loadDuo()
        let cache = try capabilities.encoded()
        print("[perf] cache size: \(cache.count) bytes")
        #expect(PerfClock.report("launch: decode cache", runs: 5) { _ = try? CaptureCapabilities.decode(cache) } < Self.bound)
        #expect(PerfClock.report("launch: encoded()", runs: 5) { _ = try? capabilities.encoded() } < Self.bound)
        let defaults = try Fixture.freshDefaults()
        #expect(PerfClock.report("launch: CameraModel.init with the real list", runs: 5) {
            _ = CameraModel(config: LaunchConfig(), capabilities: capabilities, isSimulator: true, defaults: defaults)
        } < Self.bound)
        let empty = CaptureCapabilities(lenses: [], videoOptions: [], photoOptions: [], osBuild: "", modelIdentifier: "")
        let lenses = capabilities.lenses
        #expect(PerfClock.report("launch: adopting + replaceCapabilities (device path)", runs: 5) {
            let model = CameraModel(config: LaunchConfig(), capabilities: empty, isSimulator: false, defaults: defaults)
            if let adopted = capabilities.adopting(discovered: lenses) { model.replaceCapabilities(adopted) }
        } < Self.bound)
    }

    /// The Library's first read at launch, with 300 photos and edit files for a third of them (the phone's own count is
    /// unknown here).
    @Test func libraryReload() throws {
        let dir = try TestFiles.directory()
        for number in 1...300 {
            try Data("x".utf8).write(to: dir.appending(path: String(format: "OC_%04d.HEIC", number)))
        }
        let edits = EditStore(directory: dir)
        for number in stride(from: 1, through: 300, by: 3) {
            try edits.save(PhotoEdit(), stem: String(format: "OC_%04d", number))
        }
        let library = LibraryStore(captures: try CaptureStore(directory: dir), edits: edits,
                                   looks: try LookStore(directory: TestFiles.directory()), thumbnails: ThumbnailCache(directory: try TestFiles.directory()))
        #expect(PerfClock.report("launch: library.reload() with 300 photos", runs: 5) { library.reload() } < Self.bound)
    }

    @Test func bodyReads() throws {
        let model = try readyModel()
        let reads: [(String, () -> Void)] = [
            ("recordResolver", { _ = model.recordResolver }),
            ("photoResolver", { _ = model.photoResolver }),
            ("currentVideoOption", { _ = model.currentVideoOption }),
            ("currentPhotoOption", { _ = model.currentPhotoOption }),
            ("summaryParts", { _ = model.summaryParts }),
            ("frameRateText", { _ = model.frameRateText }),
            ("remaining", { _ = model.remaining }),
            ("isStorageFull", { _ = model.isStorageFull }),
            ("canCapture", { _ = model.canCapture }),
            ("canOpenRecordSettings", { _ = model.canOpenRecordSettings }),
            ("sweepCaption", { _ = model.sweepCaption }),
            ("bottomNotice", { _ = model.bottomNotice }),
            ("sessionConfiguration", { _ = model.sessionConfiguration }),
            ("timecodeFrameRate", { _ = model.timecodeFrameRate }),
            ("droppedFrames", { _ = (model.isRecording, model.droppedFrames) }),
            ("dropChoice", { _ = model.dropChoice }),
        ]
        for (name, read) in reads {
            #expect(PerfClock.report("read: \(name)", runs: 9, read) < Self.bound)
        }
        // What each camera-screen view's body asks of the model once.
        #expect(PerfClock.report("body: BottomBar + NoticeLine (video)", runs: 9) { Self.bottomBar(model) } < Self.bound)
        #expect(PerfClock.report("body: TopReadoutBar + Timecode", runs: 9) { Self.topReadoutBar(model) } < Self.bound)
        #expect(PerfClock.report("body: FoldedVerticalVideoView", runs: 9) { Self.foldedVerticalVideo(model) } < Self.bound)
        #expect(PerfClock.report("body: CaptureButton", runs: 9) { Self.captureButton(model) } < Self.bound)
        #expect(PerfClock.report("body: StripControl x4", runs: 9) { Self.strip(model) } < Self.bound)
        // A rotation lays out a whole new layout view: its body and every child's, once.
        #expect(PerfClock.report("rotation: vertical video -> horizontal (all bodies)", runs: 9) {
            Self.topReadoutBar(model); Self.bottomBar(model); Self.captureButton(model); Self.strip(model)
            _ = (model.phase, model.viewfinderLook, model.isCameraStopped)
        } < Self.bound)
        #expect(PerfClock.report("rotation: horizontal -> vertical video (all bodies)", runs: 9) {
            Self.foldedVerticalVideo(model); Self.topReadoutBar(model); Self.captureButton(model); Self.strip(model)
        } < Self.bound)
        let photo = try readyModel(mode: .photo)
        #expect(PerfClock.report("body: FoldedVerticalView (photo)", runs: 9) { Self.foldedVerticalPhoto(photo) } < Self.bound)
    }

    @Test func selectionChanges() async throws {
        let model = try readyModel()
        let configurator = FakeSessionConfigurator(failingLensIDs: [])
        let configuration = try #require(model.sessionConfiguration)
        model.attachSession(configurator, configuredWith: configuration, selection: model.currentSelection)
        let changes: [(String, RecordRow, String, String)] = [
            ("codec", .codec, "hevc", "h264"),
            ("quality", .quality, "High", "Medium"),
            ("resolution", .resolution, "3840x2160", "1920x1080"),
            ("frame rate", .frameRate, "30", "60"),
            ("colour", .colour, "Rec. 709", "P3"),
        ]
        for (name, row, first, second) in changes {
            #expect(PerfClock.report("change: \(name)", runs: 7) {
                let resolver = model.recordResolver
                let current = resolver.chips(row, for: model.record).first { Self.isSelected($0.id, row: row, in: model.record) }?.id
                let target = current == first ? second : first
                if let changed = resolver.select(row, chipID: target, in: model.record) { model.record = changed }
            } < Self.bound)
        }
        #expect(PerfClock.report("change: lens", runs: 7) {
            model.selectLens(model.lensID == Self.wide ? Self.ultraWide : Self.wide)
        } < Self.bound)
        #expect(PerfClock.report("change: mode", runs: 7) {
            model.mode = model.mode == .video ? .photo : .video
        } < Self.bound)
        #expect(PerfClock.report("persist()", runs: 9) { model.persist() } < Self.bound)
        await model.waitForQueuedConfigures()
    }

    /// A lens's first visit builds its resolver (cold); a later visit reuses it (warm). Each run starts from a fresh model.
    @Test func lensFirstVisit() throws {
        let capabilities = try Fixture.loadDuo().withWriterOptions(.all)
        let clock = ContinuousClock()
        var coldRead: [Duration] = [], coldSwitch: [Duration] = [], warmSwitch: [Duration] = []
        for _ in 0..<7 {
            let model = CameraModel(config: LaunchConfig(), capabilities: capabilities, isSimulator: true, defaults: try Fixture.freshDefaults())
            model.phase = .ready
            coldRead.append(clock.measure { _ = model.currentVideoOption })
            coldSwitch.append(clock.measure { model.selectLens(Self.ultraWide); _ = model.summaryParts })
            model.selectLens(Self.wide)
            warmSwitch.append(clock.measure { model.selectLens(Self.ultraWide); _ = model.summaryParts })
        }
        for (name, samples) in [("lens: first read of the launch lens (cold)", coldRead), ("change: lens, first visit (cold)", coldSwitch),
                                ("change: lens, later visit (warm)", warmSwitch)] {
            let median = samples.sorted()[samples.count / 2]
            print("[perf] \(name): \(PerfClock.milliseconds(median)) ms")
            #expect(median < Self.bound)
        }
    }

    @Test func settingsSheetRender() throws {
        let model = try readyModel()
        #expect(PerfClock.report("sheet: video rows, one render", runs: 7) {
            let resolver = model.recordResolver
            for row in RecordRow.allCases {
                // As VideoRecordRows asks: chips once, the reason line from them.
                _ = resolver.chips(row, for: model.record).first { !$0.isAvailable }?.reason
            }
            if let option = resolver.option(for: model.record) { _ = DataRateEstimator.footer(for: option, freeBytes: model.freeBytes) }
        } < Self.bound)
        #expect(PerfClock.report("sheet: video rows with estimates, one render", runs: 7) {
            let resolver = model.recordResolver
            for row in RecordRow.allCases {
                _ = resolver.chips(row, for: model.record, freeBytes: model.freeBytes).first { !$0.isAvailable }?.reason
            }
            if let option = resolver.option(for: model.record) { _ = DataRateEstimator.footer(for: option, freeBytes: model.freeBytes) }
        } < Self.bound)
        #expect(PerfClock.report("sheet: photo rows, one render", runs: 7) {
            let resolver = model.photoResolver
            for row in PhotoRow.allCases {
                _ = resolver.chips(row, for: model.photo)
                _ = resolver.reasonLine(row, for: model.photo)
            }
        } < Self.bound)
    }

    // MARK: What each view reads

    private static func isSelected(_ id: String, row: RecordRow, in selection: RecordSelection) -> Bool {
        switch row {
        case .codec: id == selection.family.rawValue
        case .quality: id == selection.quality
        case .resolution: id == selection.resolution.id
        case .frameRate: id == String(selection.frameRate)
        case .colour: id == selection.colour.rawValue
        }
    }

    private static func noticeLine(_ model: CameraModel) {
        _ = model.bottomNotice
        _ = model.bottomNoticeOpensSettings
    }

    private static func bottomBar(_ model: CameraModel) {
        _ = model.summaryLookName
        _ = model.summaryParts
        _ = model.sweepCaption
        _ = model.mode
        _ = model.canOpenRecordSettings
        if model.showsVideoReadouts {
            _ = model.shownMeterLevels
            _ = model.remaining.text
            _ = model.remaining.isWarning
        }
        noticeLine(model)
    }

    private static func topReadoutBar(_ model: CameraModel) {
        _ = model.frameRateText
        _ = [ManualControl.shutter, .iso, .temperature, .tint].map { model.readout(for: $0) }
        _ = (model.timecodeFrameRate, model.isRecording, model.recordingStart)
    }

    private static func foldedVerticalVideo(_ model: CameraModel) {
        _ = (model.phase, model.viewfinderLook, model.isCameraStopped)
        if model.bottomNotice != nil { noticeLine(model) }
        _ = model.summaryParts
        _ = model.summaryLookName
        _ = model.sweepCaption
        _ = model.canOpenRecordSettings
        if !model.isStorageFull { _ = model.shownMeterLevels }
        _ = model.remaining.text
        _ = model.remaining.isWarning
        // The dropped-frames badge reads only these two.
        _ = (model.isRecording, model.droppedFrames)
    }

    private static func foldedVerticalPhoto(_ model: CameraModel) {
        _ = (model.phase, model.viewfinderLook, model.isCameraStopped)
        _ = [ManualControl.shutter, .iso, .bias, .temperature, .focus].map { model.readout(for: $0) }
        _ = model.summaryParts
        _ = model.canOpenRecordSettings
        noticeLine(model)
        captureButton(model)
    }

    private static func captureButton(_ model: CameraModel) {
        _ = model.mode
        _ = model.canCapture
        _ = model.isRecording
    }

    private static func strip(_ model: CameraModel) {
        _ = (model.mode, model.canChangeLensOrMode, model.lenses, model.currentLens, model.lensID)
        _ = model.canOpenRecordSettings
        _ = (model.canOpenLibrary, model.lastCapture)
    }
}
