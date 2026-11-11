import Foundation
import Testing
@testable import OpenCam

/// The strip's Library stack: the newest three captures, newest first, kept without reloading the Library.
@MainActor @Suite struct RecentCapturesTests {
    func model(_ store: CaptureStore) throws -> CameraModel {
        CameraModel(config: LaunchConfig(), capabilities: try Fixture.load(), isSimulator: true, defaults: try Fixture.freshDefaults(),
                    captureStore: store)
    }

    func names(_ model: CameraModel) -> [String] {
        model.recentCaptures.map(CaptureStore.clipKey(for:))
    }

    @Test func theNewestThreeAreKeptNewestFirst() throws {
        let dir = try TestFiles.directory()
        for name in ["OC_0001.HEIC", "OC_0002.JPG", "OC_0003.MOV", "OC_0003.json", "OC_0004.DNG", "OC_0004.HEIC", "OC_0004.edit.json"] {
            try Data("x".utf8).write(to: dir.appending(path: name))
        }
        let model = try model(try CaptureStore(directory: dir))
        model.loadLastCapture()
        // One entry per press: a RAW and HEIF pair shows its HEIF, and sidecars and edit files never show.
        #expect(names(model) == ["OC_0004.HEIC", "OC_0003.MOV", "OC_0002.JPG"])
        #expect(model.lastCapture.map(CaptureStore.clipKey(for:)) == "OC_0004.HEIC")

        let photo = dir.appending(path: "OC_0005.HEIC")
        try Data("x".utf8).write(to: photo)
        model.photoFinished(requested: [photo], result: PhotoCaptureResult(saved: [photo], error: nil))
        #expect(names(model) == ["OC_0005.HEIC", "OC_0004.HEIC", "OC_0003.MOV"])
        #expect(CaptureStore.recentCaptureNames(["OC_0001.HEIC", "OC_0002.HEIC"], limit: 3) == ["OC_0002.HEIC", "OC_0001.HEIC"])
    }

    /// A capture is pushed onto the list from its own file; the Library is never scanned and only that file's thumbnail is made.
    @Test func aNewCaptureDoesNotReloadTheLibrary() async throws {
        let dir = try TestFiles.directory()
        _ = try TestFiles.writeJPEG(width: 40, height: 30, rgb: SIMD3(0.5, 0.5, 0.5), to: dir.appending(path: "OC_0001.JPG"))
        let library = try LibraryStoreTests.make(dir); library.reload()
        let model = try model(library.captures)
        model.loadLastCapture()
        let reloads = library.reloadCount

        let photo = dir.appending(path: "OC_0002.JPG")
        _ = try TestFiles.writeJPEG(width: 40, height: 30, rgb: SIMD3(0.5, 0.5, 0.5), to: photo)
        model.photoFinished(requested: [photo], result: PhotoCaptureResult(saved: [photo], error: nil))
        #expect(names(model) == ["OC_0002.JPG", "OC_0001.JPG"])
        for url in model.recentCaptures {
            let image = try #require(await library.captureThumbnail(for: url))
            #expect(max(image.width, image.height) <= ThumbnailCache.longSide)
        }
        #expect(library.reloadCount == reloads); #expect(library.items.count == 1)
    }

    /// A photo deleted in the Library leaves the list when the Library closes.
    @Test func closingTheLibraryRefreshesTheList() async throws {
        let dir = try TestFiles.directory()
        for name in ["OC_0001.HEIC", "OC_0002.HEIC", "OC_0003.HEIC"] { try Data("x".utf8).write(to: dir.appending(path: name)) }
        let model = try model(try CaptureStore(directory: dir))
        model.loadLastCapture()
        #expect(names(model) == ["OC_0003.HEIC", "OC_0002.HEIC", "OC_0001.HEIC"])
        model.openLibrary(); #expect(model.isLibraryPresented)
        try FileManager.default.removeItem(at: dir.appending(path: "OC_0002.HEIC"))
        model.isLibraryPresented = false
        await model.closeLibrary()
        #expect(names(model) == ["OC_0003.HEIC", "OC_0001.HEIC"])
    }

    /// The strip finds the Library items of all its recent captures in one pass, with the same results as one file at a time.
    @Test func recentCapturesAreFoundInOnePassWithTheSameItems() throws {
        let dir = try TestFiles.directory()
        for name in ["OC_0001.DNG", "OC_0001.HEIC", "OC_0002.JPG", "OC_0003.MOV"] { try Data("x".utf8).write(to: dir.appending(path: name)) }
        let library = try LibraryStoreTests.make(dir); library.reload()
        let urls = ["OC_0001.DNG", "OC_0002.JPG", "OC_0003.MOV", "OC_0009.HEIC", "OC_0001.HEIC"].map { dir.appending(path: $0) }
        let items = library.captureItems(for: urls)
        #expect(items.map { $0.map { library.thumbnailKey(for: $0) } } == urls.map { library.captureThumbnailKey(for: $0) })
        #expect(items.map { $0 != nil } == [true, true, false, false, true])
        #expect(items[0] == items[4])
    }

    @Test func noCapturesShowsTheSymbol() throws {
        let model = try model(try CaptureStore(directory: TestFiles.directory()))
        model.loadLastCapture()
        #expect(model.recentCaptures.isEmpty); #expect(model.lastCapture == nil)
        #expect(LibraryThumbnail.showsSymbol(for: []))
        #expect(model.canOpenLibrary)
        model.openLibrary(); #expect(model.isLibraryPresented)
    }
}
