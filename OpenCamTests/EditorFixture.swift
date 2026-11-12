import Foundation
@testable import OpenCam

@MainActor enum EditorFixture {
    /// Writes a mid-grey `OC_0001.JPG` of the given size, scans it and loads an editor for it with an empty `LookStore`.
    static func make(width: Int, height: Int, now: (@Sendable () -> Date)? = nil) async throws -> (model: EditorModel, captures: URL, looks: LookStore) {
        let captures = try TestFiles.directory()
        _ = try TestFiles.writeJPEG(width: width, height: height, rgb: SIMD3(0.5, 0.5, 0.5), to: captures.appending(path: "OC_0001.JPG"))
        guard let item = LibraryScanner.items(in: captures).first else { throw TestFileError.bitmapUnavailable }
        let looks = try LookStore(directory: TestFiles.directory())
        let model = EditorModel(item: item, edits: EditStore(directory: captures), looks: looks, now: now)
        await model.load()
        return (model, captures, looks)
    }
}
