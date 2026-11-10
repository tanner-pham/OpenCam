import Foundation

nonisolated enum EditStoreError: Error, CustomStringConvertible {
    case unreadable(path: String, reason: String)
    case unwritable(path: String, reason: String)

    var description: String {
        switch self {
        case .unreadable(let path, let reason):
            "[EditStore:load] Cannot read the edit — {path: \(path), reason: \(reason)}"
        case .unwritable(let path, let reason):
            "[EditStore:write] Cannot write the edit — {path: \(path), reason: \(reason)}"
        }
    }
}
