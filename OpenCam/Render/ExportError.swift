import Foundation

nonisolated enum ExportError: Error, CustomStringConvertible, Equatable {
    case sourceMissing(path: String)
    case undecodable(path: String)
    case writeFailed(path: String, reason: String)

    var description: String {
        switch self {
        case .sourceMissing(let path):
            "[PhotoExporter:export] Original file does not exist — {path: \(path)}"
        case .undecodable(let path):
            "[PhotoExporter:export] Original file could not be decoded — {path: \(path)}"
        case .writeFailed(let path, let reason):
            "[PhotoExporter:export] Export file could not be written — {path: \(path), reason: \(reason)}"
        }
    }
}
