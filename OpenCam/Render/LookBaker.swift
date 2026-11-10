import CoreImage
import Foundation
import ImageIO

/// Bakes a look into a captured photo at full size. Runs off the main actor and keeps nothing once it returns.
nonisolated enum LookBaker {
    static let quality = 0.9

    /// Decodes upright, renders the full pipeline at full size, and encodes HEIF (Display P3, quality 0.9) with the
    /// capture metadata `PhotoExporter` carries. The only full-size copy is the one Core Image renders into the encoder.
    static func bake(_ data: Data, adjustments: Adjustments, renderer: LookRenderer = .shared) throws(LookBakeError) -> Data {
        guard let decoded = CIImage(data: data, options: [.applyOrientationProperty: true]) else {
            throw .undecodable
        }
        let properties = CGImageSourceCreateWithData(data as CFData, nil)
            .flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [String: Any] } ?? [:]
        let rendered = renderer.render(decoded, adjustments: adjustments)
        let image = rendered.settingProperties(PhotoExporter.carriedMetadata(from: properties, size: rendered.extent.size))
        let options = [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): quality]
        guard let baked = renderer.context.heifRepresentation(of: image, format: .RGBA8, colorSpace: renderer.displayP3, options: options) else {
            throw .encodeFailed
        }
        return baked
    }
}
