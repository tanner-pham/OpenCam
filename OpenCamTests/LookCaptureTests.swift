import Foundation
import Testing
@testable import OpenCam

@Suite struct LookCaptureTests {
    let look = CameraLook(id: UUID(), name: "Warm fade", adjustments: Adjustments().setting(.exposure, to: 1))

    func urls() throws -> (dir: URL, dng: URL, heic: URL) {
        let dir = try TestFiles.directory()
        return (dir, dir.appending(path: "OC_0001.DNG"), dir.appending(path: "OC_0001.HEIC"))
    }
    func grey() throws -> Data { try TestFiles.heicData(width: 400, height: 300, rgb: SIMD3(0.5, 0.5, 0.5)) }
    func centre(_ url: URL) throws -> Float { try PixelReader.rgb(PictureDecoder.full(at: url), x: 200, y: 150).x }
    func hasEditFile(_ dir: URL) -> Bool {
        FileManager.default.fileExists(atPath: EditStore(directory: dir).url(forStem: "OC_0001").path(percentEncoded: false))
    }

    @Test func heifWithALookIsBakedAndWritesNoEditFile() async throws {
        let (dir, dng, heic) = try urls()
        try grey().write(to: heic)                                   // the camera has already written the photo
        #expect(abs(try centre(heic) - 0.5) < 0.02)
        let saved = PhotoCaptureResult(saved: [heic], error: nil)
        let outcome = await LookCapture.finish(saved, look: look, format: .heif, heicURL: heic, dngURL: dng, edits: EditStore(directory: dir))
        #expect(outcome == LookCaptureOutcome(result: saved, notice: nil))
        #expect(abs(try centre(heic) - 0.686) < 0.02)
        #expect(!hasEditFile(dir))
    }
    @Test func identityLookLeavesThePhotoAndWritesNothing() async throws {
        let (dir, dng, heic) = try urls()
        let identity = CameraLook(id: UUID(), name: "Plain", adjustments: Adjustments())
        let photo = try grey(); try photo.write(to: heic)
        let heif = PhotoCaptureResult(saved: [heic], error: nil)
        let heifOutcome = await LookCapture.finish(heif, look: identity, format: .heif, heicURL: heic, dngURL: dng, edits: EditStore(directory: dir))
        #expect(heifOutcome == LookCaptureOutcome(result: heif, notice: nil))
        #expect(try Data(contentsOf: heic) == photo)
        try Data("dng bytes".utf8).write(to: dng)
        let raw = PhotoCaptureResult(saved: [dng], error: nil)
        let rawOutcome = await LookCapture.finish(raw, look: identity, format: .raw, heicURL: heic, dngURL: dng, edits: EditStore(directory: dir))
        #expect(rawOutcome == LookCaptureOutcome(result: raw, notice: nil))
        #expect(!hasEditFile(dir))
    }
    @Test func bakingFailureStillSavesThePhoto() async throws {   // Review Focus 2
        let (dir, dng, heic) = try urls()
        let written = Data("not a photo".utf8); try written.write(to: heic)
        let saved = PhotoCaptureResult(saved: [heic], error: nil)
        let outcome = await LookCapture.finish(saved, look: look, format: .heif, heicURL: heic, dngURL: dng, edits: EditStore(directory: dir))
        #expect(outcome == LookCaptureOutcome(result: saved, notice: "Look not applied. The photo was saved without it."))
        #expect(try Data(contentsOf: heic) == written)               // the file the camera wrote is untouched
    }
    @Test func rawWritesAnEditFileBesideTheUntouchedDNG() async throws {
        let (dir, dng, heic) = try urls()
        let raw = Data("dng bytes".utf8); try raw.write(to: dng)
        let saved = PhotoCaptureResult(saved: [dng], error: nil)
        let outcome = await LookCapture.finish(saved, look: look, format: .raw, heicURL: heic, dngURL: dng, edits: EditStore(directory: dir))
        #expect(outcome == LookCaptureOutcome(result: saved, notice: nil))
        #expect(try EditStore(directory: dir).load(stem: "OC_0001") == PhotoEdit(adjustments: look.adjustments, lookName: "Warm fade"))
        #expect(try Data(contentsOf: dng) == raw)
    }
    @Test func rawPlusHEIFBakesTheHEIFAndWritesNoEditFile() async throws {   // Review Focus 4
        let (dir, dng, heic) = try urls()
        let raw = Data("dng bytes".utf8); try raw.write(to: dng); try grey().write(to: heic)
        let saved = PhotoCaptureResult(saved: [dng, heic], error: nil)
        let outcome = await LookCapture.finish(saved, look: look, format: .rawPlusHEIF, heicURL: heic, dngURL: dng, edits: EditStore(directory: dir))
        #expect(outcome == LookCaptureOutcome(result: saved, notice: nil))
        #expect(abs(try centre(heic) - 0.686) < 0.02); #expect(try Data(contentsOf: dng) == raw)
        #expect(!hasEditFile(dir))
    }
    @Test func rawPlusHEIFWithoutItsHEIFGetsNeitherABakeNorAnEditFile() async throws {
        let (dir, dng, heic) = try urls()
        let raw = Data("dng bytes".utf8); try raw.write(to: dng)
        let partial = PhotoCaptureResult(saved: [dng], error: .noPhotoData)
        let outcome = await LookCapture.finish(partial, look: look, format: .rawPlusHEIF, heicURL: heic, dngURL: dng, edits: EditStore(directory: dir))
        #expect(outcome == LookCaptureOutcome(result: partial, notice: nil))
        #expect(!hasEditFile(dir)); #expect(try Data(contentsOf: dng) == raw)
        #expect(!FileManager.default.fileExists(atPath: heic.path(percentEncoded: false)))
    }
    @Test func editFileFailureKeepsTheDNG() async throws {
        let (dir, dng, heic) = try urls()
        try Data("dng bytes".utf8).write(to: dng)
        let saved = PhotoCaptureResult(saved: [dng], error: nil)
        let outcome = await LookCapture.finish(saved, look: look, format: .raw, heicURL: heic, dngURL: dng,
                                               edits: EditStore(directory: dir.appending(path: "missing", directoryHint: .isDirectory)))
        #expect(outcome == LookCaptureOutcome(result: saved, notice: "Look not saved with the photo."))
        #expect(FileManager.default.fileExists(atPath: dng.path(percentEncoded: false)))
    }
    @Test func failedCapturesAreLeftAsTheyAre() async throws {
        let (dir, dng, heic) = try urls()
        let failed = PhotoCaptureResult(saved: [], error: .noPhotoData)
        for format in [PhotoFormat.heif, .raw, .rawPlusHEIF] {
            #expect(await LookCapture.finish(failed, look: look, format: format, heicURL: heic, dngURL: dng, edits: EditStore(directory: dir))
                    == LookCaptureOutcome(result: failed, notice: nil))
        }
        #expect(!hasEditFile(dir))
    }
}

/// The model cannot be handed a fake photo session (it holds a `CameraSession`), so these deliver the result to
/// `photoFinished` directly: the notice rules are the whole of what the model adds.
@MainActor @Suite struct LookCaptureNoticeTests {
    func model() throws -> CameraModel {
        CameraModel(config: LaunchConfig(), capabilities: try Fixture.load(), isSimulator: true, defaults: try Fixture.freshDefaults())
    }
    let heic = URL(filePath: "/tmp/OC_0001.HEIC")
    let dng = URL(filePath: "/tmp/OC_0001.DNG")

    @Test func theLooksNoticeShowsWhenTheSaveWasComplete() throws {
        let model = try model()
        model.photoFinished(requested: [heic], result: PhotoCaptureResult(saved: [heic], error: nil), lookNotice: LookCapture.lookNotApplied)
        #expect(model.notice == LookCapture.lookNotApplied)
    }
    @Test func theSaveReportsNoticeWinsOverTheLooks() throws {
        let model = try model()
        model.photoFinished(requested: [dng, heic], result: PhotoCaptureResult(saved: [dng], error: .noPhotoData), lookNotice: LookCapture.lookNotApplied)
        #expect(model.notice == PhotoSaveReport.heifNotSaved)
    }
    @Test func withNoLookNoticeAFullSaveClearsAnEarlierCaptureNotice() throws {
        let model = try model()
        model.photoFinished(requested: [heic], result: PhotoCaptureResult(saved: [], error: .noPhotoData))
        #expect(model.notice == PhotoSaveReport.photoNotSaved)
        model.photoFinished(requested: [heic], result: PhotoCaptureResult(saved: [heic], error: nil))
        #expect(model.notice == nil); #expect(model.lastCapture == heic)
    }
}
