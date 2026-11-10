import CoreImage
import Foundation
import ImageIO

/// Writes a photo's edit, baked in at full size, to a new file outside Captures for sharing. The original is never written.
/// The one place a full-size render happens: it runs off the main actor and keeps nothing once the file is written.
nonisolated struct PhotoExporter: Sendable {
    let directory: URL
    private let renderer: LookRenderer

    private static let quality = 0.9

    /// `tmp/Export`, created when an export first needs it.
    static func appDefault() -> PhotoExporter {
        PhotoExporter(directory: FileManager.default.temporaryDirectory.appending(path: "Export", directoryHint: .isDirectory))
    }

    init(directory: URL, renderer: LookRenderer = .shared) {
        self.directory = directory
        self.renderer = renderer
    }

    /// "<stem>-edited.HEIC", or ".JPG" for a JPEG original, in `directory`, replacing an older export of that name.
    /// The picture is decoded upright, so the file carries no orientation tag; it is Display P3 at quality 0.9.
    @concurrent func export(_ item: LibraryItem, edit: PhotoEdit) async throws(ExportError) -> URL {
        let source = item.pictureURL
        let decoded: CIImage
        do {
            decoded = try PictureDecoder.full(at: source)
        } catch {
            switch error {
            case .missing: throw .sourceMissing(path: source.path(percentEncoded: false))
            case .undecodable: throw .undecodable(path: source.path(percentEncoded: false))
            }
        }
        let format = ExportFormat.of(source)
        let url = directory.appending(path: "\(item.stem)-edited.\(format.rawValue)", directoryHint: .notDirectory)
        // The rendered image carries none of the original's properties, so no orientation tag (or other metadata) is written.
        let image = renderer.render(decoded, adjustments: edit.adjustments)
        let options = [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): Self.quality]
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
                try FileManager.default.removeItem(at: url)
            }
            // Core Image renders straight into the encoder; no full-size bitmap is kept here.
            switch format {
            case .heif:
                try renderer.context.writeHEIFRepresentation(of: image, to: url, format: .RGBA8, colorSpace: renderer.displayP3, options: options)
            case .jpeg:
                try renderer.context.writeJPEGRepresentation(of: image, to: url, colorSpace: renderer.displayP3, options: options)
            }
        } catch {
            throw .writeFailed(path: url.path(percentEncoded: false), reason: error.localizedDescription)
        }
        return url
    }
}
