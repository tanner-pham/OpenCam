import Foundation

enum TestFiles {
    /// A new empty folder under the temporary directory.
    static func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "OpenCamTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
