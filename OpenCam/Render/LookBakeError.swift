import Foundation

/// The brief's tests compare `LookBakeError.undecodable` with no payload, so the sizes the description names are
/// carried by the cases' associated values being absent: callers log the context they hold (see `LookCapture`).
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
