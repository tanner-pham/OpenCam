import Foundation

/// The file extension of each kind of capture file.
nonisolated enum CaptureFileKind: String, Sendable {
    case dng = "DNG"
    case heic = "HEIC"
    case jpg = "JPG"
    case png = "PNG"
    case mov = "MOV"
    case sidecar = "json"
}
