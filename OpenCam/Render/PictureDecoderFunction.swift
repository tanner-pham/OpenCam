import Foundation

/// The `PictureDecoder` function that threw, named in `PictureError` messages.
nonisolated enum PictureDecoderFunction: String, Sendable {
    case full, proxy, pixelSize
}
