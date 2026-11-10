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
        let rendered = renderer.render(decoded, adjustments: edit.adjustments)
        // Core Image would otherwise write the decoded image's properties as they are, including the original's pixel
        // dimensions and subject area; the export's metadata is chosen here instead.
        let image = rendered.settingProperties(Self.carriedMetadata(from: source, size: rendered.extent.size))
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

    /// The original's capture metadata for the export: Exif (date and time, exposure, lens), TIFF (make, model), GPS and
    /// IPTC. Orientation and pixel dimensions are the export's own (upright, `size`). Whatever describes the unedited pixels
    /// is left out: maker notes, the subject area (coordinates in the original's orientation), embedded thumbnails and the
    /// colour profile, which is the export's Display P3.
    private static func carriedMetadata(from source: URL, size: CGSize) -> [String: Any] {
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any]
        else { return [:] }
        var metadata: [String: Any] = [:]
        if var exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            exif[kCGImagePropertyExifSubjectArea as String] = nil
            exif[kCGImagePropertyExifPixelXDimension as String] = Int(size.width)
            exif[kCGImagePropertyExifPixelYDimension as String] = Int(size.height)
            metadata[kCGImagePropertyExifDictionary as String] = exif
        }
        if var tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
            tiff[kCGImagePropertyTIFFOrientation as String] = nil
            metadata[kCGImagePropertyTIFFDictionary as String] = tiff
        }
        for key in [kCGImagePropertyGPSDictionary, kCGImagePropertyIPTCDictionary] {
            if let dictionary = properties[key as String] { metadata[key as String] = dictionary }
        }
        return metadata
    }
}
