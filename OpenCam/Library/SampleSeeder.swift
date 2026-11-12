import CoreImage
import Foundation
import ImageIO
import SwiftUI

/// Writes three generated pictures into an empty Captures folder, so the Library can be shown in the Simulator.
@MainActor enum SampleSeeder {
    static let size = CGSize(width: 672, height: 504)
    static let scale: CGFloat = 3

    /// 0 when the folder already has any photo or clip. Otherwise OC_0001 is colour bars, OC_0002 a hue sweep and OC_0003 the
    /// drawn scene, so the newest item is the scene. A picture that cannot be rendered or written throws `.seedFailed`.
    static func seedIfEmpty(_ captures: CaptureStore) throws(LibraryError) -> Int {
        guard LibraryScanner.items(in: captures.directory).isEmpty else { return 0 }
        try write(ColourBarsPattern(), to: captures.url(sequence: captures.reserveSequence(), kind: .jpg))
        try write(HueSweepPattern(), to: captures.url(sequence: captures.reserveSequence(), kind: .jpg))
        try write(ViewfinderStandIn(showsCaption: false), to: captures.url(sequence: captures.reserveSequence(), kind: .jpg))
        return 3
    }

    private static func write(_ content: some View, to url: URL) throws(LibraryError) {
        let path = url.path(percentEncoded: false)
        let renderer = ImageRenderer(content: content.frame(width: size.width, height: size.height))
        renderer.scale = scale
        guard let image = renderer.cgImage else { throw .seedFailed(function: "seedIfEmpty", path: path, reason: "The picture could not be rendered") }
        let context = LookRenderer.shared.context
        let quality = CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String)
        guard let data = context.jpegRepresentation(of: CIImage(cgImage: image), colorSpace: LookRenderer.shared.displayP3, options: [quality: 0.9]) else {
            throw .seedFailed(function: "seedIfEmpty", path: path, reason: "The picture could not be encoded")
        }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw .seedFailed(function: "seedIfEmpty", path: path, reason: error.localizedDescription)
        }
    }
}
