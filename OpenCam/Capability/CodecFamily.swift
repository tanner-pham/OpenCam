import Foundation

nonisolated enum CodecFamily: String, Codable, Sendable, Hashable, CaseIterable {
    case raw
    case proRes
    case hevc
    case h264

    var title: String {
        switch self {
        case .raw: "RAW"
        case .proRes: "ProRes"
        case .hevc: "HEVC"
        case .h264: "H.264"
        }
    }
}
