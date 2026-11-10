import Foundation

nonisolated struct VideoCodec: Codable, Sendable, Hashable {
    let family: CodecFamily
    let quality: String
    let codecType: String
    let bitrateTier: BitrateTier?

    var displayName: String {
        switch family {
        case .raw: quality
        case .proRes: "\(family.title) \(quality)"
        case .hevc, .h264: "\(family.title) \(bitrateTier?.rawValue ?? quality)"
        }
    }
}
