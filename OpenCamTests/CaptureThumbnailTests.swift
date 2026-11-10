import CoreImage
import Foundation
import Testing
@testable import OpenCam

/// The camera strip's last-capture picture of a photo comes from the same cache, with the same edit, as its Library cell.
@MainActor @Suite struct CaptureThumbnailTests {
    @Test func aPhotoShowsItsEditAsInTheLibrary() async throws {
        let dir = try TestFiles.directory()
        let url = dir.appending(path: "OC_0001.JPG")
        _ = try TestFiles.writeJPEG(width: 400, height: 300, rgb: SIMD3(0.5, 0.5, 0.5), to: url)
        try EditStore(directory: dir).save(PhotoEdit(adjustments: Adjustments().setting(.exposure, to: 1)), stem: "OC_0001")
        let store = try LibraryStoreTests.make(dir); store.reload()

        let strip = try #require(await store.captureThumbnail(for: url))
        guard case .ready(let cell) = await store.thumbnail(for: try #require(store.items.first)) else {
            Issue.record("the Library cell must render"); return
        }
        #expect(strip.width == cell.width); #expect(strip.height == cell.height)
        let stripCentre = try PixelReader.rgb(CIImage(cgImage: strip), x: strip.width / 2, y: strip.height / 2)
        let cellCentre = try PixelReader.rgb(CIImage(cgImage: cell), x: cell.width / 2, y: cell.height / 2)
        #expect(abs(stripCentre.x - cellCentre.x) < 0.01)
        // Exposure +1 on mid-grey, not the unedited 0.5.
        #expect(abs(stripCentre.x - 0.686) < 0.03)
    }

    /// The strip asks again when the photo's edit changes, because the request's key carries the edit.
    @Test func theKeyFollowsTheEdit() throws {
        let dir = try TestFiles.directory()
        let url = dir.appending(path: "OC_0001.JPG")
        _ = try TestFiles.writeJPEG(width: 40, height: 30, rgb: SIMD3(0.5, 0.5, 0.5), to: url)
        let store = try LibraryStoreTests.make(dir); store.reload()
        let plain = try #require(store.captureThumbnailKey(for: url))
        try EditStore(directory: dir).save(PhotoEdit(adjustments: Adjustments().setting(.exposure, to: 1)), stem: "OC_0001")
        store.reload()
        #expect(try #require(store.captureThumbnailKey(for: url)) != plain)
    }

    /// A photo taken since the last reload is still found; a clip is left to the strip's own preview.
    @Test func aNewPhotoIsFoundAndAClipIsNot() async throws {
        let dir = try TestFiles.directory()
        let store = try LibraryStoreTests.make(dir); store.reload()
        let photo = dir.appending(path: "OC_0002.JPG")
        _ = try TestFiles.writeJPEG(width: 40, height: 30, rgb: SIMD3(0.5, 0.5, 0.5), to: photo)
        #expect(await store.captureThumbnail(for: photo) != nil)
        let clip = dir.appending(path: "OC_0003.MOV")
        try Data("x".utf8).write(to: clip)
        #expect(await store.captureThumbnail(for: clip) == nil); #expect(store.captureThumbnailKey(for: clip) == nil)
    }
}
