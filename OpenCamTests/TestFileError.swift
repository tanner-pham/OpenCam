import Foundation

enum TestFileError: Error, CustomStringConvertible {
    case colourUnavailable
    case bitmapUnavailable
    case encoderUnavailable(type: String)
    case pixelOutsideImage(x: Int, y: Int)

    var description: String {
        switch self {
        case .colourUnavailable: "[TestFiles:patch] Cannot make a Display P3 colour — {}"
        case .bitmapUnavailable: "[TestFiles:encode] Cannot draw the bitmap — {}"
        case .encoderUnavailable(let type): "[TestFiles:encode] Cannot encode this type — {type: \(type)}"
        case .pixelOutsideImage(let x, let y): "[PixelReader:rgb] Pixel is outside the image — {x: \(x), y: \(y)}"
        }
    }
}
