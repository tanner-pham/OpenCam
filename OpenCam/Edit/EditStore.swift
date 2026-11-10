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

    /// An empty `PhotoEdit` when the file is missing.
    func load(stem: String) throws(EditStoreError) -> PhotoEdit {
        let url = url(forStem: stem)
        let path = url.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else { return PhotoEdit() }
        do {
            return try JSONDecoder().decode(PhotoEdit.self, from: Data(contentsOf: url))
        } catch {
            throw .unreadable(path: path, reason: error.localizedDescription)
        }
    }

    /// Writes atomically. An edit with nothing in it removes the file instead.
    func save(_ edit: PhotoEdit, stem: String) throws(EditStoreError) {
        if edit.isIdentity { return try remove(stem: stem) }
        let url = url(forStem: stem)
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
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            throw .unwritable(path: path, reason: error.localizedDescription)
        }
    }
}
