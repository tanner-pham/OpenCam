import Foundation
import Testing
@testable import OpenCam

/// The sweep loop against a fake camera: the device runs it for real; this checks the order and the report.
@MainActor @Suite struct FormatSweepRunTests {
    let lens = Lens(id: "wide", kind: .wide, deviceUniqueID: "W", zoomFactor: 1, label: "1x")
    let proRes = VideoOption(lensID: "wide", codec: VideoCodec(family: .proRes, quality: "422 HQ", codecType: "apch", bitrateTier: nil), resolution: .named(width: 3840, height: 2160), frameRate: 30, colour: .appleLog2)
    let hevc = VideoOption(lensID: "wide", codec: VideoCodec(family: .hevc, quality: "High", codecType: "hvc1", bitrateTier: .high), resolution: .named(width: 3840, height: 2160), frameRate: 30, colour: .rec709)

    func makeStore() throws -> CaptureStore {
        try CaptureStore(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
    }

    func readReport(_ url: URL?) throws -> SweepReport {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SweepReport.self, from: Data(contentsOf: try #require(url)))
    }

    @Test func aFailingOptionDoesNotStopTheSweep() async throws {
        let store = try makeStore()
        let driver = FakeSweepDriver(directory: store.directory, failingCodecs: ["apch"])
        let sweep = FormatSweep(driver: driver, store: store, lens: lens, options: [proRes, hevc], keepsClips: false, clipDuration: .milliseconds(10))
        driver.sweep = sweep
        #expect(sweep.progressText == "0 of 2")
        await sweep.run()
        #expect(!sweep.isRunning); #expect(sweep.done == 2); #expect(sweep.progressText == "2 of 2")
        #expect(sweep.rows.map(\.status) == [.fail, .pass])
        #expect(sweep.rows[0].error == "Recording failed."); #expect(sweep.rows[0].detail?.hasPrefix("[CameraSession:configure]") == true)
        #expect(driver.applied == [hevc]); #expect(driver.stopCount == 1)
        let names = try FileManager.default.contentsOfDirectory(atPath: store.directory.path(percentEncoded: false))
        #expect(!names.contains("OC_0001.MOV"))
        let report = try readReport(sweep.reportURL)
        #expect(!report.cancelled); #expect(report.rows == sweep.rows); #expect(report.lensID == "wide")
        let name = try #require(sweep.reportURL?.lastPathComponent)
        #expect(sweep.resultText == "Done. 1 passed, 1 failed. Saved \(name).")
    }

    let h264 = VideoOption(lensID: "wide", codec: VideoCodec(family: .h264, quality: "High", codecType: "avc1", bitrateTier: .high), resolution: .named(width: 1920, height: 1080), frameRate: 30, colour: .rec709)
    let fast = SweepDeadlines(start: .milliseconds(200), finish: .milliseconds(50), cancelGrace: .milliseconds(10))

    @Test func aClipWhoseResultNeverArrivesFailsAndTheSweepContinues() async throws {
        let store = try makeStore()
        let driver = FakeSweepDriver(directory: store.directory, failingCodecs: [], hangingCodecs: ["apch"])
        let sweep = FormatSweep(driver: driver, store: store, lens: lens, options: [proRes, hevc], keepsClips: false,
                                clipDuration: .milliseconds(10), deadlines: fast)
        driver.sweep = sweep
        await sweep.run()
        #expect(sweep.rows.map(\.status) == [.fail, .pass]); #expect(sweep.done == 2)
        #expect(sweep.rows[0].error == "The clip did not finish."); #expect(sweep.rows[0].detail?.hasPrefix("[FormatSweep:run]") == true)
        // The hung clip is stopped once when its time is up and once more when its deadline passes.
        #expect(driver.stopCount == 3)
        let report = try readReport(sweep.reportURL)
        #expect(!report.cancelled); #expect(!report.endedEarly)
    }

    @Test func twoTimeoutsInARowEndTheSweepAndUnlockTheControls() async throws {
        let store = try makeStore()
        let model = CameraModel(config: LaunchConfig(), capabilities: try Fixture.load(), isSimulator: true, defaults: try Fixture.freshDefaults(),
                                capabilitySource: tempSource())
        let userRecord = model.record
        let driver = FakeSweepDriver(directory: store.directory, failingCodecs: [], hangingCodecs: ["apch", "hvc1"])
        let sweep = FormatSweep(driver: driver, store: store, lens: lens, options: [proRes, hevc, h264], keepsClips: false,
                                clipDuration: .milliseconds(10), deadlines: fast)
        driver.sweep = sweep
        await model.runSweep(sweep, lensID: lens.id)
        #expect(sweep.rows.map(\.error) == ["The clip did not finish.", "The clip did not finish."]); #expect(sweep.done == 2)
        let report = try readReport(sweep.reportURL)
        #expect(report.endedEarly); #expect(!report.cancelled); #expect(report.rows.count == 2)
        let name = try #require(sweep.reportURL?.lastPathComponent)
        #expect(sweep.resultText == "Stopped after 2 of 3. The camera stopped responding. Saved \(name).")
        #expect(!sweep.isRunning); #expect(!model.isSweeping); #expect(model.canChangeLensOrMode); #expect(model.record == userRecord)
        #expect(model.failedCombinations.caption(for: proRes) != nil)
    }

    @Test func cancelDuringAHungClipEndsTheWaitAndUnlocks() async throws {
        let store = try makeStore()
        let model = CameraModel(config: LaunchConfig(), capabilities: try Fixture.load(), isSimulator: true, defaults: try Fixture.freshDefaults(),
                                capabilitySource: tempSource())
        let driver = FakeSweepDriver(directory: store.directory, failingCodecs: [], hangingCodecs: ["apch"])
        // A finish deadline far longer than the test: only Cancel can end this wait quickly.
        let slow = SweepDeadlines(start: .seconds(60), finish: .seconds(60), cancelGrace: .milliseconds(10))
        let sweep = FormatSweep(driver: driver, store: store, lens: lens, options: [proRes, hevc], keepsClips: false,
                                clipDuration: .milliseconds(10), deadlines: slow)
        driver.sweep = sweep
        // Cancel once the clip has been stopped and the sweep is waiting on its result.
        driver.onClipStarted = { Task { try? await Task.sleep(for: .milliseconds(100)); sweep.cancel() } }
        let started = ContinuousClock.now
        await model.runSweep(sweep, lensID: lens.id)
        #expect(ContinuousClock.now - started < .seconds(5))
        #expect(sweep.rows.map(\.error) == ["The clip did not finish."])
        let report = try readReport(sweep.reportURL)
        #expect(report.cancelled); #expect(!report.endedEarly)
        let name = try #require(sweep.reportURL?.lastPathComponent)
        #expect(sweep.resultText == "Cancelled after 1 of 2. Saved \(name).")
        #expect(!model.isSweeping); #expect(model.canChangeLensOrMode)
    }

    func tempSource() -> CapabilitySource {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        return CapabilitySource(cacheDirectory: directory, documentsDirectory: nil, discoverLenses: { [] }, scan: { _ in [] })
    }

    @Test func theSimulatorCannotStartASweepOrRescan() throws {
        let model = CameraModel(config: .parse(["app", "-screen", "sweep"]), capabilities: try Fixture.load(), isSimulator: true, defaults: try Fixture.freshDefaults())
        #expect(model.sheet == .sweep); #expect(!model.canStartSweep); #expect(!model.canRescanCapabilities)
        #expect(!model.isSweeping); #expect(model.sweepCaption == nil)
        // Every option of the lens a selection can reach, and only that lens.
        let options = model.sweepOptions
        #expect(!options.isEmpty); #expect(options.allSatisfy { $0.lensID == model.lensID })
        #expect(Set(options).count == options.count)
    }

    @Test func sweepRowNotesUseTheRightGrammar() {
        func row(dropped: Int?) -> SweepRow {
            SweepRow.evaluate(requested: hevc, facts: ClipFacts(codecFourCC: "hvc1", width: 3840, height: 2160, nominalFrameRate: 30, durationSeconds: 3,
                                                                frameCount: 90, droppedFrames: dropped, colour: .rec709, megabitsPerSecond: 50, hasAudio: true), error: nil)
        }
        #expect(SweepView.note(for: row(dropped: 0)) == nil); #expect(SweepView.note(for: row(dropped: nil)) == nil)
        #expect(SweepView.note(for: row(dropped: 1)) == "Dropped 1 frame."); #expect(SweepView.note(for: row(dropped: 4)) == "Dropped 4 frames.")
        #expect(SweepView.title(of: hevc) == "HEVC High, 4K, 30 fps, Rec. 709")
    }

    @Test func cancelFinishesTheCurrentClipAndWritesACancelledReport() async throws {
        let store = try makeStore()
        let driver = FakeSweepDriver(directory: store.directory, failingCodecs: [])
        let sweep = FormatSweep(driver: driver, store: store, lens: lens, options: [proRes, hevc], keepsClips: true, clipDuration: .milliseconds(10))
        driver.sweep = sweep
        driver.onClipStarted = { sweep.cancel() }
        await sweep.run()
        #expect(sweep.rows.map(\.status) == [.pass]); #expect(sweep.done == 1); #expect(driver.stopCount == 1)
        #expect(FileManager.default.fileExists(atPath: store.directory.appending(path: "OC_0001.MOV").path(percentEncoded: false)))
        let report = try readReport(sweep.reportURL)
        #expect(report.cancelled)
        let name = try #require(sweep.reportURL?.lastPathComponent)
        #expect(sweep.resultText == "Cancelled after 1 of 2. Saved \(name).")
    }
}
