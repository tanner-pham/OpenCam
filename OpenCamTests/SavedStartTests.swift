import Foundation
import Testing
@testable import OpenCam

/// The record that lets the next launch start the session before capabilities are read. It is used only when it is exactly
/// what this launch would resolve.
@MainActor @Suite struct SavedStartTests {
    private static let build = "BUILD1", device = "Duo1"
    private static let authorized = CaptureAccess(camera: .authorized, microphone: .authorized)

    private func base() throws -> (SessionConfiguration, RecordSelection, PhotoSelection) {
        let model = CameraModel(config: LaunchConfig(), capabilities: try Fixture.load(), isSimulator: false, defaults: try Fixture.freshDefaults())
        return (try #require(model.sessionConfiguration), model.record, model.photo)
    }

    /// A record and the selections it was saved with.
    private func make(mode: CaptureMode = .video, colour: ColourMode = .rec709, includesAudio: Bool = true,
                      needsFrames: Bool = false, scanVersion: Int = CaptureCapabilities.currentScanVersion) throws -> (SavedStart, SavedSelections) {
        var (configuration, record, photo) = try base()
        configuration.mode = mode
        configuration.includesAudio = includesAudio
        configuration.needsFrames = needsFrames
        record.colour = colour
        let start = SavedStart(configuration: configuration, record: record, photo: photo, osBuild: Self.build, modelIdentifier: Self.device, scanVersion: scanVersion)
        return (start, SavedSelections(mode: mode, lensID: configuration.lens.id, record: record, photo: photo))
    }

    private func use(_ start: SavedStart, _ saved: SavedSelections?, access: CaptureAccess = SavedStartTests.authorized, hasLook: Bool = false,
                     build: String = SavedStartTests.build, device: String = SavedStartTests.device) -> SessionConfiguration? {
        start.configuration(for: saved, access: access, hasLook: hasLook, osBuild: build, modelIdentifier: device)
    }

    @Test func aRecordRoundTripsThroughDefaults() throws {
        let defaults = try Fixture.freshDefaults()
        let (start, _) = try make()
        start.save(to: defaults)
        #expect(SavedStart.load(from: defaults) == start)
        SavedStart.clear(from: defaults)
        #expect(SavedStart.load(from: defaults) == nil)
        defaults.set(Data("not a record".utf8), forKey: SavedStart.key)
        #expect(SavedStart.load(from: defaults) == nil)
    }

    @Test func aRecordIsUsedOnlyOnItsOwnBuildModelAndScan() throws {
        let (start, saved) = try make()
        #expect(use(start, saved) == start.configuration)
        #expect(use(start, saved, build: "BUILD2") == nil)
        #expect(use(start, saved, device: "Duo2") == nil)
        let (older, olderSaved) = try make(scanVersion: CaptureCapabilities.currentScanVersion - 1)
        #expect(use(older, olderSaved) == nil)
    }

    @Test func aRecordIsUsedOnlyForTheSelectionSavedNow() throws {
        let (start, saved) = try make()
        #expect(use(start, nil) == nil)
        var other = saved; other.mode = .photo
        #expect(use(start, other) == nil)
        other = saved; other.lensID = "another lens"
        #expect(use(start, other) == nil)
        other = saved; other.record.frameRate += 1
        #expect(use(start, other) == nil)
        other = saved; other.photo.megapixels += 1
        #expect(use(start, other) == nil)
        other = saved; other.look = CameraLook(id: UUID(), name: "Warm", adjustments: Adjustments())
        #expect(use(start, other) == start.configuration)
    }

    @Test func aRecordIsUsedOnlyWithTheAccessItWasBuiltFor() throws {
        let (withSound, saved) = try make(includesAudio: true)
        let (silent, silentSaved) = try make(includesAudio: false)
        for state in [AccessState.notDetermined, .denied, .restricted] {
            #expect(use(withSound, saved, access: CaptureAccess(camera: state, microphone: .authorized)) == nil)
        }
        #expect(use(withSound, saved, access: CaptureAccess(camera: .authorized, microphone: .notDetermined)) == nil)
        #expect(use(withSound, saved, access: CaptureAccess(camera: .authorized, microphone: .denied)) == nil)
        #expect(use(silent, silentSaved, access: CaptureAccess(camera: .authorized, microphone: .authorized)) == nil)
        #expect(use(silent, silentSaved, access: CaptureAccess(camera: .authorized, microphone: .denied)) == silent.configuration)
        #expect(use(withSound, saved) == withSound.configuration)
    }

    @Test func aRecordIsUsedOnlyWhenItsFramesMatchTheLook() throws {
        let (noFrames, noFramesSaved) = try make(colour: .rec709, needsFrames: false)
        #expect(use(noFrames, noFramesSaved, hasLook: true) == nil)
        let (frames, framesSaved) = try make(colour: .rec709, needsFrames: true)
        #expect(use(frames, framesSaved, hasLook: false) == nil)
        #expect(use(frames, framesSaved, hasLook: true) == frames.configuration)
        let (log, logSaved) = try make(colour: .appleLog, needsFrames: false)
        #expect(use(log, logSaved, hasLook: true) == log.configuration)
        let (photo, photoSaved) = try make(mode: .photo, needsFrames: true)
        #expect(use(photo, photoSaved, hasLook: true) == photo.configuration)
    }
}
