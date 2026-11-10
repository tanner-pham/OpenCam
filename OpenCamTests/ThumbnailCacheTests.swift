import Foundation
import Testing
@testable import OpenCam

@Suite struct ThumbnailCacheTests {
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    @Test func keyFollowsNameDateAndEdit() {
        let plain = ThumbnailCache.key(fileName: "OC_0001.HEIC", modified: date, edit: PhotoEdit())
        #expect(plain.hasPrefix("OC_0001.HEIC-1800000000000-")); #expect(plain.hasSuffix(".jpg")); #expect(!plain.contains("/"))
        #expect(plain == ThumbnailCache.key(fileName: "OC_0001.HEIC", modified: date, edit: PhotoEdit()))
        #expect(plain != ThumbnailCache.key(fileName: "OC_0001.HEIC", modified: date.addingTimeInterval(1), edit: PhotoEdit()))
        #expect(plain != ThumbnailCache.key(fileName: "OC_0001.HEIC", modified: date, edit: PhotoEdit(adjustments: Adjustments().setting(.exposure, to: 0.1))))
        #expect(plain != ThumbnailCache.key(fileName: "OC_0002.HEIC", modified: date, edit: PhotoEdit()))
    }
    @Test func rendersAt360AndCaches() async throws {
        let captures = try TestFiles.directory(), cacheDirectory = try TestFiles.directory()
        _ = try TestFiles.writeJPEG(width: 1200, height: 800, rgb: SIMD3(0.5, 0.5, 0.5), to: captures.appending(path: "OC_0001.JPG"))
        let item = try #require(LibraryScanner.items(in: captures).first)
        let image = try await ThumbnailCache(directory: cacheDirectory).thumbnail(for: item, edit: PhotoEdit())
        #expect(image.width == 360); #expect(image.height == 240)
        let key = ThumbnailCache.key(fileName: "OC_0001.JPG", modified: item.modified, edit: PhotoEdit())
        #expect(FileManager.default.fileExists(atPath: cacheDirectory.appending(path: key).path(percentEncoded: false)))
    }
}
