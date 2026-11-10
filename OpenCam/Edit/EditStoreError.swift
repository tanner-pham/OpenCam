import Foundation

nonisolated enum EditStoreError: Error, CustomStringConvertible, Equatable {
    case unreadable(path: String, reason: String)
    case newerVersion(path: String, version: Int)
    case unwritable(path: String, reason: String)

    var description: String {
        switch self {
        case .unreadable(let path, let reason):
            "[EditStore:load] Cannot read the edit — {path: \(path), reason: \(reason)}"
        case .newerVersion(let path, let version):
            "[EditStore:write] Edit file was written by a newer version and is read-only here — {path: \(path), version: \(version), supported: \(PhotoEdit.currentVersion)}"
        case .unwritable(let path, let reason):
            "[EditStore:write] Cannot write the edit — {path: \(path), reason: \(reason)}"
        }
    }
}
