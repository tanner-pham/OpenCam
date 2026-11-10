import Foundation

/// What an import did: the new files, and how many pictures could not be imported.
nonisolated struct ImportResult: Sendable, Equatable {
    let imported: [URL]
    let failed: Int

    /// The sentence to show, or nil when nothing was chosen.
    var message: String? { LibraryCopy.importResult(imported: imported.count, failed: failed) }
}
