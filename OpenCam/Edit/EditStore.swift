import Foundation

/// Edits as `<stem>.edit.json` files beside the captures they belong to. The original is never touched.
nonisolated struct EditStore: Sendable {
    let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    /// "OC_0001.edit.json"
    static func fileName(forStem stem: String) -> String { stem + ".edit.json" }

    func url(forStem stem: String) -> URL {
        directory.appending(path: Self.fileName(forStem: stem), directoryHint: .notDirectory)
    }

    /// An empty `PhotoEdit` when the file is missing. A file from a newer build whose shape this build cannot decode throws
    /// `.newerVersion`; any other file that cannot be read or decoded throws `.unreadable`.
    func load(stem: String) throws(EditStoreError) -> PhotoEdit {
        let url = url(forStem: stem)
        let path = url.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else { return PhotoEdit() }
        let data = try Self.read(url)
        do {
            return try JSONDecoder().decode(PhotoEdit.self, from: data)
        } catch {
            if let version = Self.storedVersion(in: data), version > PhotoEdit.currentVersion {
                throw .newerVersion(path: path, version: version)
            }
            throw .unreadable(path: path, reason: error.localizedDescription)
        }
    }

    /// Writes atomically. An edit with nothing in it removes the file instead.
    func save(_ edit: PhotoEdit, stem: String) throws(EditStoreError) {
        if edit.isIdentity { return try remove(stem: stem) }
        let url = url(forStem: stem)
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) { try refuseUnwritable(url) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try encoder.encode(edit).write(to: url, options: .atomic)
        } catch {
            throw .unwritable(path: url.path(percentEncoded: false), reason: error.localizedDescription)
        }
    }

    /// A missing file is not an error.
    func remove(stem: String) throws(EditStoreError) {
        let url = url(forStem: stem)
        let path = url.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else { return }
        try refuseUnwritable(url)
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            throw .unwritable(path: path, reason: error.localizedDescription)
        }
    }

    /// An existing file this build cannot fully read is read-only here, so its data is never overwritten or removed: one
    /// written by a newer build (`.newerVersion`, whatever its shape) and one that cannot be read or decoded (`.unreadable`).
    private func refuseUnwritable(_ url: URL) throws(EditStoreError) {
        let path = url.path(percentEncoded: false)
        let data = try Self.read(url)
        guard let version = Self.storedVersion(in: data) else {
            throw .unreadable(path: path, reason: "The file has no readable version")
        }
        if version > PhotoEdit.currentVersion { throw .newerVersion(path: path, version: version) }
        do {
            _ = try JSONDecoder().decode(PhotoEdit.self, from: data)
        } catch {
            throw .unreadable(path: path, reason: error.localizedDescription)
        }
    }

    private static func read(_ url: URL) throws(EditStoreError) -> Data {
        do {
            return try Data(contentsOf: url)
        } catch {
            throw .unreadable(path: url.path(percentEncoded: false), reason: error.localizedDescription)
        }
    }

    /// The file's version alone, read without its shape (a missing version is 1); nil when the bytes are not a JSON object
    /// or the version is not a number.
    private static func storedVersion(in data: Data) -> Int? {
        (try? JSONDecoder().decode(EditFileVersion.self, from: data)).map { $0.version ?? 1 }
    }
}
