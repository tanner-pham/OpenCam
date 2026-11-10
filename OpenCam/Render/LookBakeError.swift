import Foundation

/// Why a bake failed. The cases carry no values; `LookCapture` logs the context (path and byte count) when it catches one.
nonisolated enum LookBakeError: Error, CustomStringConvertible, Equatable {
    case undecodable
    case encodeFailed

    var description: String {
        switch self {
        case .undecodable:
            "[LookBaker:bake] Photo data could not be decoded"
        case .encodeFailed:
            "[LookBaker:bake] The baked photo could not be encoded"
        }
    }
}
