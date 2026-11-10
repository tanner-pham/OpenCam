import CoreGraphics
import Foundation
import Testing
@testable import OpenCam

@MainActor @Suite struct SampleSeederTests {
    @Test func seedsThreePicturesOnlyIntoAnEmptyLibrary() throws {
        let dir = try TestFiles.directory(); let captures = try CaptureStore(directory: dir)
        #expect(try SampleSeeder.seedIfEmpty(captures) == 3)
        #expect(LibraryScanner.items(in: dir).map(\.pictureURL.lastPathComponent) == ["OC_0003.JPG", "OC_0002.JPG", "OC_0001.JPG"])
        #expect(try SampleSeeder.seedIfEmpty(captures) == 0)
        #expect(try PictureDecoder.pixelSize(at: dir.appending(path: "OC_0003.JPG")) == CGSize(width: 2016, height: 1512))
        let clipOnly = try TestFiles.directory()
        try Data("x".utf8).write(to: clipOnly.appending(path: "OC_0001.MOV"))
        #expect(try SampleSeeder.seedIfEmpty(CaptureStore(directory: clipOnly)) == 0)   // a clip is a library item
    }
}
