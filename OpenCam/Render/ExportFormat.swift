import Foundation

/// The file type an export is written as; the raw value is its file extension.
nonisolated enum ExportFormat: String, Sendable {
    case heif = "HEIC", jpeg = "JPG"

    /// A JPEG original exports as JPEG; anything else (HEIC, HEIF, PNG, DNG) as HEIF.
    static func of(_ pictureURL: URL) -> ExportFormat {
        ["JPG", "JPEG"].contains(pictureURL.pathExtension.uppercased()) ? .jpeg : .heif
    }
}
