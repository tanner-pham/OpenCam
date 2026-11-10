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

    /// An import can finish after the Library has closed and the camera read its last capture; the store counts finished
    /// imports so the camera reads it again, and then shows the imported photo.
    @Test func aFinishedImportIsCountedSoTheCameraReadsTheLastCaptureAgain() async throws {
        let dir = try TestFiles.directory()
        try Data("x".utf8).write(to: dir.appending(path: "OC_0001.JPG"))
        let store = try LibraryStoreTests.make(dir); store.reload()
        let model = CameraModel(config: LaunchConfig(), capabilities: try Fixture.load(), isSimulator: true, defaults: try Fixture.freshDefaults(),
                                captureStore: store.captures)
        model.refreshLastCapture()
        #expect(model.lastCapture?.lastPathComponent == "OC_0001.JPG"); #expect(store.importsFinished == 0)
        let jpeg = try TestFiles.jpegData(width: 16, height: 16, rgb: SIMD3(0.5, 0.5, 0.5))
        _ = await store.importPhotos([jpeg]) { ImportCandidate(data: $0, contentType: .jpeg) }
        #expect(store.importsFinished == 1)
        model.libraryImportFinished()
        #expect(model.lastCapture?.lastPathComponent == "OC_0002.JPG")
    }

    /// A photo taken since the last reload is still found; a clip is left to the strip's own preview.
    /// Taking a photo or stopping a clip never scans the library: a new photo is drawn from its own file and edit file
    /// alone, with that edit, and a clip is left to the strip's own preview at once.
    @Test func aNewCaptureNeverReloadsTheLibrary() async throws {
        let dir = try TestFiles.directory()
        let store = try LibraryStoreTests.make(dir); store.reload()
        let reloads = store.reloadCount
        let photo = dir.appending(path: "OC_0002.JPG")
        _ = try TestFiles.writeJPEG(width: 40, height: 30, rgb: SIMD3(0.5, 0.5, 0.5), to: photo)
        try EditStore(directory: dir).save(PhotoEdit(adjustments: Adjustments().setting(.exposure, to: 1)), stem: "OC_0002")
        let image = try #require(await store.captureThumbnail(for: photo))
        #expect(abs(try PixelReader.rgb(CIImage(cgImage: image), x: image.width / 2, y: image.height / 2).x - 0.686) < 0.03)
        let clip = dir.appending(path: "OC_0003.MOV")
        try Data("x".utf8).write(to: clip)
        #expect(await store.captureThumbnail(for: clip) == nil); #expect(store.captureThumbnailKey(for: clip) == nil)
        #expect(await store.captureThumbnail(for: clip) == nil)
        #expect(store.reloadCount == reloads); #expect(store.items.isEmpty)
    }
}
