import Foundation
import Testing
import UniformTypeIdentifiers
@testable import OpenCam

@MainActor @Suite struct PhotoImporterTests {
    @Test func importsKeepTheirBytesAndContinueTheSequence() async throws {
        let dir = try TestFiles.directory()
        try Data("x".utf8).write(to: dir.appending(path: "OC_0004.HEIC"))
        let jpeg = try TestFiles.jpegData(width: 40, height: 30, rgb: SIMD3(0.8, 0.2, 0.2)), png = try TestFiles.pngData(width: 30, height: 40, rgb: SIMD3(0.2, 0.8, 0.2))
        let result = await PhotoImporter.importCandidates([ImportCandidate(data: jpeg, contentType: .jpeg), ImportCandidate(data: png, contentType: .png)],
                                                    into: try CaptureStore(directory: dir))
        #expect(result.imported.map(\.lastPathComponent) == ["OC_0005.JPG", "OC_0006.PNG"]); #expect(result.failed == 0)
        #expect(try Data(contentsOf: dir.appending(path: "OC_0005.JPG")) == jpeg); #expect(result.message == "Imported 2 photos.")
    }
    @Test func heicKeepsItsBytesToo() async throws {
        let dir = try TestFiles.directory()
        let heic = try TestFiles.heicData(width: 32, height: 24, rgb: SIMD3(0.2, 0.2, 0.8))
        let result = await PhotoImporter.importCandidates([ImportCandidate(data: heic, contentType: .heic)], into: try CaptureStore(directory: dir))
        #expect(result.imported.map(\.lastPathComponent) == ["OC_0001.HEIC"]); #expect(result.message == "Imported 1 photo.")
        #expect(try Data(contentsOf: dir.appending(path: "OC_0001.HEIC")) == heic)
    }
    @Test func undecodableImportFailsAndLeavesCapturesUntouched() async throws {   // Review Focus 4
        let dir = try TestFiles.directory()
        try Data("x".utf8).write(to: dir.appending(path: "OC_0001.HEIC"))
        let before = try FileManager.default.contentsOfDirectory(atPath: dir.path(percentEncoded: false)).sorted()
        let captures = try CaptureStore(directory: dir)
        let result = await PhotoImporter.importCandidates([ImportCandidate(data: Data("not a picture".utf8), contentType: .jpeg),
                                                     ImportCandidate(data: try TestFiles.tiffData(width: 8, height: 8, rgb: SIMD3(0.5, 0.5, 0.5)), contentType: .tiff)], into: captures)
        #expect(result.imported.isEmpty); #expect(result.failed == 2); #expect(result.message == "2 photos could not be imported.")
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path(percentEncoded: false)).sorted() == before)
        #expect(await PhotoImporter.importCandidates([ImportCandidate(data: Data("x".utf8), contentType: .heic)], into: captures).message == "The photo could not be imported.")
        #expect(captures.reserveSequence() == 2)   // failures used no number
    }
    @Test func aFailureBesideASuccessKeepsTheSuccess() async throws {
        let dir = try TestFiles.directory()
        let jpeg = try TestFiles.jpegData(width: 16, height: 16, rgb: SIMD3(0.5, 0.5, 0.5))
        let result = await PhotoImporter.importCandidates([ImportCandidate(data: Data("no".utf8), contentType: .jpeg), ImportCandidate(data: jpeg, contentType: .jpeg)],
                                                    into: try CaptureStore(directory: dir))
        #expect(result.imported.map(\.lastPathComponent) == ["OC_0001.JPG"]); #expect(result.failed == 1)
        #expect(result.message == "Imported 1 photo. 1 could not be imported.")
    }
    @Test func theBytesDecideTheExtensionNotTheDeclaredType() async throws {
        let dir = try TestFiles.directory()
        let jpeg = try TestFiles.jpegData(width: 16, height: 16, rgb: SIMD3(0.5, 0.5, 0.5))
        let result = await PhotoImporter.importCandidates([ImportCandidate(data: jpeg, contentType: .heic)], into: try CaptureStore(directory: dir))
        #expect(result.imported.map(\.lastPathComponent) == ["OC_0001.JPG"]); #expect(try Data(contentsOf: dir.appending(path: "OC_0001.JPG")) == jpeg)
    }
    @Test func anImportNeverReplacesAnExistingFileAndLeavesNoTemporaryFile() async throws {
        let dir = try TestFiles.directory()
        let captures = try CaptureStore(directory: dir)
        try Data("keep me".utf8).write(to: dir.appending(path: "OC_0001.JPG"))
        let before = try FileManager.default.contentsOfDirectory(atPath: dir.path(percentEncoded: false)).sorted()
        let jpeg = try TestFiles.jpegData(width: 16, height: 16, rgb: SIMD3(0.5, 0.5, 0.5))
        let result = await PhotoImporter.importCandidates([ImportCandidate(data: jpeg, contentType: .jpeg)], into: captures)
        #expect(result.imported.isEmpty); #expect(result.failed == 1)
        #expect(try Data(contentsOf: dir.appending(path: "OC_0001.JPG")) == Data("keep me".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path(percentEncoded: false)).sorted() == before)
    }
    /// Thirty ProRAW files would not fit in memory at once: each picked item is loaded, imported and released before the next
    /// one loads.
    @Test func aBatchHoldsOnePictureAtATime() async throws {
        let dir = try TestFiles.directory()
        let jpeg = try TestFiles.jpegData(width: 64, height: 48, rgb: SIMD3(0.4, 0.5, 0.6))
        let counter = LiveBufferCounter()
        var aliveAtEachLoad: [Int] = []
        let result = await PhotoImporter.importEach(Array(0..<5), into: try CaptureStore(directory: dir)) { index in
            aliveAtEachLoad.append(counter.count)
            // The third item cannot be loaded; it counts as one that could not be imported.
            return index == 2 ? nil : ImportCandidate(data: counter.data(copying: jpeg), contentType: .jpeg)
        }
        #expect(aliveAtEachLoad == [0, 0, 0, 0, 0]); #expect(counter.count == 0)
        #expect(result.imported.map(\.lastPathComponent) == ["OC_0001.JPG", "OC_0002.JPG", "OC_0003.JPG", "OC_0004.JPG"])
        #expect(result.failed == 1); #expect(result.message == "Imported 4 photos. 1 could not be imported.")
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
