import Foundation

nonisolated enum LibraryError: Error, CustomStringConvertible, Equatable {
    case deleteFailed(path: String, reason: String)
    case editFailed(stem: String, reason: String)
    /// From `EditStoreError.newerVersion`; shown as `LibraryCopy.newerEdit`.
    case newerEdit(path: String, version: Int)
    /// Apply look or Remove look could not change some photos; `change` says what happened to every item.
    case lookChangeIncomplete(change: LookChange, reason: String)
    /// A sample that could not be rendered or written.
    case seedFailed(path: String, reason: String)

    var description: String {
        switch self {
        case .deleteFailed(let path, let reason):
            "[LibraryStore:delete] Cannot delete the file — {path: \(path), reason: \(reason)}"
        case .editFailed(let stem, let reason):
            "[LibraryStore:delete] Cannot remove the edit — {stem: \(stem), reason: \(reason)}"
        case .lookChangeIncomplete(let change, let reason):
            "[LibraryStore:\(change.action == .applied ? "applyLook" : "removeLook")] Some photos could not be changed — {changed: \(change.photosChanged), failed: \(change.photosFailed), first reason: \(reason)}"
        case .newerEdit(let path, let version):
            "[LibraryStore:delete] Edit was written by a newer version, so the photo was kept — {path: \(path), version: \(version)}"
        case .seedFailed(let path, let reason):
            "[SampleSeeder:seedIfEmpty] Cannot create the sample — {path: \(path), reason: \(reason)}"
        }
    }
}
