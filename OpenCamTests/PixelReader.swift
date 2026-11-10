import CoreImage
import Foundation
@testable import OpenCam

enum PixelReader {
    /// One pixel, rendered as RGBA floats in Display P3 through the app's shared context. Core Image coordinates (origin at the bottom left).
    static func rgb(_ image: CIImage, x: Int, y: Int) throws -> SIMD3<Float> {
        let bounds = CGRect(x: x, y: y, width: 1, height: 1)
        guard image.extent.contains(bounds) else { throw TestFileError.pixelOutsideImage(x: x, y: y) }
        let renderer = LookRenderer.shared
        var pixel = [Float](repeating: 0, count: 4)
        renderer.context.render(image, toBitmap: &pixel, rowBytes: 4 * MemoryLayout<Float>.size, bounds: bounds, format: .RGBAf, colorSpace: renderer.displayP3)
        return SIMD3(pixel[0], pixel[1], pixel[2])
    }
}
