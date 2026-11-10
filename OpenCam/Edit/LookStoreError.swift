import Foundation

nonisolated enum LookStoreError: Error, CustomStringConvertible, Equatable {
    case emptyName
    case nameTooLong(count: Int)
    case notFound(id: UUID)
    case unwritable(path: String, reason: String)
    case directoryUnavailable(reason: String)

    var description: String {
        switch self {
        case .emptyName:
            "[LookStore:validName] Look name is empty — {}"
        case .nameTooLong(let count):
            "[LookStore:validName] Look name is too long — {count: \(count), max: \(LookStore.maxNameLength)}"
        case .notFound(let id):
            "[LookStore:read] Look does not exist — {id: \(id.uuidString)}"
        case .unwritable(let path, let reason):
            "[LookStore:write] Cannot write the look — {path: \(path), reason: \(reason)}"
        case .directoryUnavailable(let reason):
            "[LookStore:init] Looks folder is unavailable — {reason: \(reason)}"
        }
    }
}
