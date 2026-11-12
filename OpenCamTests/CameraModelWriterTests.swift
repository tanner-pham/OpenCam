import Foundation
import Testing
@testable import OpenCam

/// The model's routing between the system recorder and the writer, against a fake session and the phone's merged option list.
@MainActor @Suite struct CameraModelWriterTests {
    static let size = Resolution.named(width: 3840, height: 2160)

    func deviceModel(_ fake: FakeSessionConfigurator, mode: CaptureMode = .video) throws -> CameraModel {
        let capabilities = try Fixture.loadDuo().withWriterOptions(.all)
        let model = CameraModel(config: LaunchConfig(), capabilities: capabilities, isSimulator: false, defaults: try Fixture.freshDefaults(),
                                captureStore: try CaptureStore(directory: TestFiles.directory()))
        model.mode = mode
        model.phase = .ready
        model.viewfinderSettle = .milliseconds(20)
        model.attachSession(fake, configuredWith: try #require(model.sessionConfiguration), selection: model.currentSelection)
        return model
    }

    func pick(_ family: CodecFamily, _ quality: String, _ colour: ColourMode) -> RecordSelection {
        RecordSelection(family: family, quality: quality, resolution: Self.size, frameRate: 30, colour: colour)
    }

    func proRes(_ model: CameraModel) { model.record = pick(.proRes, "422 HQ", .hlg) }
    func hevc(_ model: CameraModel) { model.record = pick(.hevc, "High", .rec709) }

    func removeClips(of fake: FakeSessionConfigurator) async {
        for url in await fake.recordingURLs { try? FileManager.default.removeItem(at: url) }
    }

    @Test func aProResSelectionAsksForTheWriter() throws {
        let model = try deviceModel(FakeSessionConfigurator(failingLensIDs: []))
        hevc(model)
        #expect(model.recorderPath == .system); #expect(model.sessionConfiguration?.recorder == .system)
        proRes(model)
        #expect(model.recorderPath == .writer); #expect(model.sessionConfiguration?.recorder == .writer)
        model.record = pick(.hevc, "High", .log)
        #expect(model.recorderPath == .writer)
    }

    @Test func photoModeNeverAsksForTheWriter() throws {
        let model = try deviceModel(FakeSessionConfigurator(failingLensIDs: []))
        proRes(model)
        #expect(model.recorderPath == .writer)
        model.mode = .photo
        #expect(model.recorderPath == .system); #expect(model.sessionConfiguration?.recorder == .system)
    }

    @Test func switchingPathsIsOneConfigureBehindTheBlur() async throws {
        let fake = FakeSessionConfigurator(failingLensIDs: [])
        let model = try deviceModel(fake)
        hevc(model)
        await model.waitForQueuedConfigures()
        let before = await fake.applied.count
        model.manual.bias = 1   // moved by hand: a configure must return it to automatic
        proRes(model)
        #expect(model.isViewfinderChanging)
        await model.waitForQueuedConfigures()
        hevc(model)
        #expect(model.isViewfinderChanging)
        await model.waitForQueuedConfigures()
        let applied = await fake.applied
        #expect(applied.suffix(2).map(\.recorder) == [.writer, .system])
        #expect(applied.count == before + 2)
        let paths = Array(applied.suffix(3))
        for pair in zip(paths, paths.dropFirst()) { #expect(ViewfinderChange.pausesPicture(from: pair.0, to: pair.1)) }
        #expect(model.manual == .automatic)
        #expect(await eventually { !model.isViewfinderChanging })
    }

    @Test func theStartCarriesTheDropPolicy() async throws {
        let fake = FakeSessionConfigurator(failingLensIDs: [])
        let model = try deviceModel(fake)
        #expect(model.dropPolicy == .keepRecording)
        proRes(model)
        await model.waitForQueuedConfigures()
        model.dropPolicy = .stopRecording
        await (try #require(model.startRecording())).value
        let recordings = await fake.recordings
        #expect(recordings.count == 1)
        #expect(recordings.first?.dropPolicy == .stopRecording)
        #expect(recordings.first?.option.codec.family == .proRes)
        await removeClips(of: fake)
    }

    @Test func aDropCountShowsOnlyForTheClipBeingRecorded() async throws {
        let fake = FakeSessionConfigurator(failingLensIDs: [])
        let model = try deviceModel(fake)
        proRes(model)
        await model.waitForQueuedConfigures()
        // Idle: ignored.
        model.apply(.framesDropped(clip: "OC_0001", total: 9))
        #expect(model.droppedFrames == 0)
        await (try #require(model.startRecording())).value
        let key = try #require(model.recordingClip.map { CaptureStore.clipKey(for: $0.url) })
        model.apply(.framesDropped(clip: "another clip", total: 7))
        #expect(model.droppedFrames == 0)
        model.apply(.framesDropped(clip: key, total: 4))
        #expect(model.droppedFrames == 4)
        // A sweep clip never shows a count.
        model.sweepClips.insert(key)
        model.apply(.framesDropped(clip: key, total: 6))
        #expect(model.droppedFrames == 4)
        model.sweepClips.remove(key)
        // The next start reads 0.
        let url = try #require(model.recordingClip?.url)
        let option = try #require(model.recordingClip?.option)
        model.recordingDidFinish(RecordingResult(url: url, option: option, outcome: .completed, sidecar: nil))
        model.apply(.framesDropped(clip: key, total: 5))
        #expect(model.droppedFrames == 4)   // idle again: ignored
        await (try #require(model.startRecording())).value
        #expect(model.droppedFrames == 0)
        await removeClips(of: fake)
    }

    @Test func aClipStoppedForDropsSaysSoAndIsKept() async throws {
        let fake = FakeSessionConfigurator(failingLensIDs: [])
        let model = try deviceModel(fake)
        proRes(model)
        await model.waitForQueuedConfigures()
        await (try #require(model.startRecording())).value
        // A selection change during the clip is held back.
        hevc(model)
        let url = try #require(model.recordingClip?.url)
        let option = try #require(model.recordingClip?.option)
        FileManager.default.createFile(atPath: url.path(percentEncoded: false), contents: Data("x".utf8))
        let before = await fake.applied.count
        model.recordingDidFinish(RecordingResult(url: url, option: option, outcome: .stopped(.droppedFrames, isPlayable: true), sidecar: nil))
        #expect(model.notice == RecordingOutcome.droppedFramesStopNotice)
        #expect(model.lastCapture != nil); #expect(!model.isRecording)
        await model.waitForQueuedConfigures()
        #expect(await fake.applied.count == before + 1)
        #expect(await fake.applied.last?.recorder == .system)
        await removeClips(of: fake)
        try? FileManager.default.removeItem(at: url)
    }

    @Test func aLookIsTurnedOffOnTheWriterPath() async throws {
        let fake = FakeSessionConfigurator(failingLensIDs: [])
        let model = try deviceModel(fake)
        let look = Look(id: UUID(), name: "Warm", adjustments: Adjustments().setting(.temperature, to: 20), createdAt: .now)
        model.looks = [look]
        hevc(model)
        model.selectLook(look.id)
        #expect(model.cameraLook != nil)
        proRes(model)
        #expect(model.cameraLook == nil)
        #expect(model.notice == LookAvailability.turnedOffForRecorder)
        #expect(!model.needsFrames); #expect(model.sessionConfiguration?.needsFrames == false)
        let chips = model.lookChips
        #expect(chips.first?.isAvailable == true)
        #expect(chips.dropFirst().allSatisfy { !$0.isAvailable && $0.reason == LookAvailability.needsSystemRecorder })
        #expect(model.lookReason == LookAvailability.needsSystemRecorder)
    }

    @Test func theSweepNeverRecordsAWriterOption() throws {
        let model = try deviceModel(FakeSessionConfigurator(failingLensIDs: []))
        let writerOptions = Set(model.capabilities.writerOptions)
        #expect(!writerOptions.isEmpty)
        #expect(model.sweepOptions.allSatisfy { !writerOptions.contains($0) })
        let resolver = model.recordResolver
        #expect(model.sweepOptions.allSatisfy { resolver.recorder(for: RecordSelection(family: $0.codec.family, quality: $0.codec.quality, resolution: $0.resolution, frameRate: $0.frameRate, colour: $0.colour)) == .system })
    }
}
