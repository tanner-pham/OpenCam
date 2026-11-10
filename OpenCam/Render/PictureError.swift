import Foundation

nonisolated enum PictureError: Error, CustomStringConvertible, Equatable {
    case missing(path: String, in: PictureDecoderFunction)
    case undecodable(path: String, in: PictureDecoderFunction)

    var description: String {
        switch self {
        case .missing(let path, let function):
            "[PictureDecoder:\(function.rawValue)] Picture file does not exist — {path: \(path)}"
        case .undecodable(let path, let function):
            "[PictureDecoder:\(function.rawValue)] Picture file could not be decoded — {path: \(path)}"
        }
    }
}
