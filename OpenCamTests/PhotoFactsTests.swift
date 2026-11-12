import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import OpenCam

@Suite struct PhotoFactsTests {
    let exif: [CFString: Any] = [kCGImagePropertyExifLensModel: "Sample lens 6.9mm f/1.8", kCGImagePropertyExifFNumber: 1.8,
                                 kCGImagePropertyExifExposureTime: 1.0 / 120, kCGImagePropertyExifISOSpeedRatings: [100],
                                 kCGImagePropertyExifFocalLength: 6.86, kCGImagePropertyExifFocalLenIn35mmFilm: 24]
    @Test func readsLensAndExposureFromExif() async throws {
        for type in [UTType.heic, .jpeg] {
            let url = try TestFiles.writeOrientedPicture(width: 32, height: 24, orientation: 1, type: type,
                                                         metadata: [kCGImagePropertyExifDictionary: exif], to: TestFiles.directory().appending(path: "OC_0001.\(type == .heic ? "HEIC" : "JPG")"))
            let facts = await PhotoFacts.read(at: url); #expect(facts.lensModel == "Sample lens 6.9mm f/1.8"); #expect(facts.equivalentFocalLength == 24); #expect(facts.iso == 100)
            #expect(facts.summary(FormatDesignation(picture: .heif, hasRAW: true)) == "RAW + HEIF · 24 mm · f/1.8 · 1/120 s · ISO 100")
            #expect(facts.rows(nil).map(\.title) == ["Lens", "Focal length", "Equivalent focal length", "Aperture", "Shutter", "ISO"]); #expect(facts.rows(nil)[1].value == "6.9 mm")
        }
    }
    @Test func factsTheFileDoesNotCarryAreLeftOut() async throws {
        let dir = try TestFiles.directory(); let plain = try TestFiles.writeJPEG(width: 16, height: 16, rgb: SIMD3(0.5, 0.5, 0.5), to: dir.appending(path: "OC_0002.JPG"))
        #expect(await PhotoFacts.read(at: plain) == .none); #expect(PhotoFacts.none.summary(FormatDesignation(picture: .jpeg, hasRAW: false)) == "JPEG")
        #expect(PhotoFacts.none.rows(FormatDesignation(picture: .jpeg, hasRAW: false)) == [PhotoInfoRow(title: "Format", value: "JPEG")])
        #expect(await PhotoFacts.read(at: dir.appending(path: "missing.HEIC")) == .none); let partial = try TestFiles.writeOrientedPicture(width: 16, height: 16, orientation: 1, type: .jpeg,
            metadata: [kCGImagePropertyExifDictionary: [kCGImagePropertyExifFNumber: 0, kCGImagePropertyExifFocalLength: 4.2]], to: dir.appending(path: "OC_0003.JPG"))
        #expect(await PhotoFacts.read(at: partial).summary(nil) == "4.2 mm")          // f/0 is not a fact
    }
    @Test func formatsShutterApertureAndFocal() {
        #expect(PhotoFacts.shutterText(seconds: 1.0 / 120) == "1/120 s"); #expect(PhotoFacts.shutterText(seconds: 0.5) == "1/2 s")
        #expect(PhotoFacts.shutterText(seconds: 2) == "2 s"); #expect(PhotoFacts.shutterText(seconds: 2.5) == "2.5 s")
        #expect(PhotoFacts.shutterText(seconds: 0.8) == "0.8 s"); #expect(PhotoFacts.shutterText(seconds: 0.4) == "0.4 s")
        #expect(PhotoFacts.shutterText(seconds: 1e-320) != ""); #expect(PhotoFacts.shutterText(seconds: .infinity) != ""); #expect(PhotoFacts.shutterText(seconds: .nan) != "")
        #expect(PhotoFacts.apertureText(1.78) == "f/1.8"); #expect(PhotoFacts.apertureText(2) == "f/2")
        #expect(PhotoFacts.millimetresText(6.86) == "6.9 mm"); #expect(PhotoFacts.millimetresText(24) == "24 mm")
    }
    @MainActor @Test func editorReadsTheFactsOfItsPhoto() async throws {
        let (model, _, _) = try await EditorFixture.make(width: 64, height: 48); #expect(model.designation?.title == "JPEG"); #expect(model.facts == .none)
    }
    @Test func outOfRangeExposureFactsAreLeftOut() async throws {
        let url = try TestFiles.writeOrientedPicture(width: 16, height: 16, orientation: 1, type: .jpeg,
            metadata: [kCGImagePropertyExifDictionary: [kCGImagePropertyExifExposureTime: 1e-320, kCGImagePropertyExifFNumber: 1.8]],
            to: TestFiles.directory().appending(path: "OC_0001.JPG"))
        let facts = await PhotoFacts.read(at: url); #expect(facts.exposureTime == nil); #expect(facts.aperture == 1.8)
        #expect(facts.summary(nil) == "f/1.8")
    }
    @MainActor @Test func editorLoadReadsFactsFromExif() async throws {
        let dir = try TestFiles.directory()
        _ = try TestFiles.writeOrientedPicture(width: 32, height: 24, orientation: 1, type: .jpeg, metadata: [kCGImagePropertyExifDictionary: exif],
                                               to: dir.appending(path: "OC_0001.JPG"))
        guard let item = LibraryScanner.items(in: dir).first else { throw TestFileError.bitmapUnavailable }
        let model = EditorModel(item: item, edits: EditStore(directory: dir), looks: try LookStore(directory: TestFiles.directory()))
        await model.load()
        #expect(model.phase == .ready); #expect(model.facts.aperture == 1.8)
    }
    @MainActor @Test func readOnlyPhotoStillShowsItsFacts() async throws {
        let dir = try TestFiles.directory()
        _ = try TestFiles.writeOrientedPicture(width: 32, height: 24, orientation: 1, type: .jpeg, metadata: [kCGImagePropertyExifDictionary: exif],
                                               to: dir.appending(path: "OC_0001.JPG"))
        try Data(#"{"version": 99, "adjustments": {}}"#.utf8).write(to: dir.appending(path: "OC_0001.edit.json"))
        guard let item = LibraryScanner.items(in: dir).first else { throw TestFileError.bitmapUnavailable }
        let model = EditorModel(item: item, edits: EditStore(directory: dir), looks: try LookStore(directory: TestFiles.directory()))
        await model.load()
        #expect(model.phase == .failed(LibraryCopy.newerEdit)); #expect(model.facts.aperture == 1.8)
    }
}
