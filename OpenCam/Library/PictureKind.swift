import Foundation

/// The kind of picture file a photo is shown from.
nonisolated enum PictureKind: String, Sendable {
    case heif = "HEIF"
    case jpeg = "JPEG"
    case png = "PNG"

    /// From a file extension in any case: HEIC and HEIF, JPG and JPEG, PNG. Nil for anything else, DNG included.
    init?(fileExtension: String) {
        switch fileExtension.uppercased() {
        case "HEIC", "HEIF": self = .heif
        case "JPG", "JPEG": self = .jpeg
        case "PNG": self = .png
        default: return nil
        }
    }
}
