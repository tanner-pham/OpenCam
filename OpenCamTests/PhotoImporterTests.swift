import Foundation
import Testing
import UniformTypeIdentifiers
@testable import OpenCam

@MainActor @Suite struct PhotoImporterTests {
    @Test func importsKeepTheirBytesAndContinueTheSequence() throws {
        let dir = try TestFiles.directory()
        try Data("x".utf8).write(to: dir.appending(path: "OC_0004.HEIC"))
        let jpeg = try TestFiles.jpegData(width: 40, height: 30, rgb: SIMD3(0.8, 0.2, 0.2)), png = try TestFiles.pngData(width: 30, height: 40, rgb: SIMD3(0.2, 0.8, 0.2))
        let result = PhotoImporter.importCandidates([ImportCandidate(data: jpeg, contentType: .jpeg), ImportCandidate(data: png, contentType: .png)],
                                                    into: try CaptureStore(directory: dir))
        #expect(result.imported.map(\.lastPathComponent) == ["OC_0005.JPG", "OC_0006.PNG"]); #expect(result.failed == 0)
        #expect(try Data(contentsOf: dir.appending(path: "OC_0005.JPG")) == jpeg); #expect(result.message == "Imported 2 photos.")
    }
    @Test func heicKeepsItsBytesToo() throws {
        let dir = try TestFiles.directory()
        let heic = try TestFiles.heicData(width: 32, height: 24, rgb: SIMD3(0.2, 0.2, 0.8))
        let result = PhotoImporter.importCandidates([ImportCandidate(data: heic, contentType: .heic)], into: try CaptureStore(directory: dir))
        #expect(result.imported.map(\.lastPathComponent) == ["OC_0001.HEIC"]); #expect(result.message == "Imported 1 photo.")
        #expect(try Data(contentsOf: dir.appending(path: "OC_0001.HEIC")) == heic)
    }
    @Test func undecodableImportFailsAndLeavesCapturesUntouched() throws {   // Review Focus 4
        let dir = try TestFiles.directory()
        try Data("x".utf8).write(to: dir.appending(path: "OC_0001.HEIC"))
        let before = try FileManager.default.contentsOfDirectory(atPath: dir.path(percentEncoded: false)).sorted()
        let captures = try CaptureStore(directory: dir)
        let result = PhotoImporter.importCandidates([ImportCandidate(data: Data("not a picture".utf8), contentType: .jpeg),
                                                     ImportCandidate(data: try TestFiles.tiffData(width: 8, height: 8, rgb: SIMD3(0.5, 0.5, 0.5)), contentType: .tiff)], into: captures)
        #expect(result.imported.isEmpty); #expect(result.failed == 2); #expect(result.message == "2 photos could not be imported.")
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path(percentEncoded: false)).sorted() == before)
        #expect(PhotoImporter.importCandidates([ImportCandidate(data: Data("x".utf8), contentType: .heic)], into: captures).message == "The photo could not be imported.")
        #expect(captures.reserveSequence() == 2)   // failures used no number
    }
    @Test func aFailureBesideASuccessKeepsTheSuccess() throws {
        let dir = try TestFiles.directory()
        let jpeg = try TestFiles.jpegData(width: 16, height: 16, rgb: SIMD3(0.5, 0.5, 0.5))
        let result = PhotoImporter.importCandidates([ImportCandidate(data: Data("no".utf8), contentType: .jpeg), ImportCandidate(data: jpeg, contentType: .jpeg)],
                                                    into: try CaptureStore(directory: dir))
        #expect(result.imported.map(\.lastPathComponent) == ["OC_0001.JPG"]); #expect(result.failed == 1)
        #expect(result.message == "Imported 1 photo. 1 could not be imported.")
    }
    @Test func fileKinds() throws {
        #expect(PhotoImporter.fileKind(for: .heic) == .heic); #expect(PhotoImporter.fileKind(for: .heif) == .heic)
        #expect(PhotoImporter.fileKind(for: .jpeg) == .jpg); #expect(PhotoImporter.fileKind(for: .png) == .png)
        #expect(PhotoImporter.fileKind(for: try #require(UTType("com.adobe.raw-image"))) == .dng)
        #expect(PhotoImporter.fileKind(for: .tiff) == nil); #expect(PhotoImporter.fileKind(for: .gif) == nil)
    }
    @Test func messages() {
        #expect(LibraryCopy.importResult(imported: 0, failed: 0) == nil); #expect(LibraryCopy.importResult(imported: 1, failed: 0) == "Imported 1 photo.")
        #expect(LibraryCopy.importResult(imported: 3, failed: 0) == "Imported 3 photos.")
        #expect(LibraryCopy.importResult(imported: 2, failed: 1) == "Imported 2 photos. 1 could not be imported.")
        #expect(LibraryCopy.importResult(imported: 0, failed: 1) == "The photo could not be imported.")
        #expect(LibraryCopy.importResult(imported: 0, failed: 2) == "2 photos could not be imported.")
    }
}
