import Foundation

nonisolated enum PictureError: Error, CustomStringConvertible, Equatable {
    case missing(path: String)
    case undecodable(path: String)

    var description: String {
        switch self {
        case .missing(let path):
            "[PictureDecoder:decode] Picture file does not exist — {path: \(path)}"
        case .undecodable(let path):
            "[PictureDecoder:decode] Picture file could not be decoded — {path: \(path)}"
        }
    }
}
