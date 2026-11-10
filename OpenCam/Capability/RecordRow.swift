import Foundation

nonisolated enum RecordRow: CaseIterable, Sendable {
    case codec, quality, resolution, frameRate, colour

    /// Grid columns per row, so wrapped rows line up. Wide is the horizontal layout.
    func columns(isWide: Bool) -> Int {
        switch self {
        case .codec: 4
        case .quality: isWide ? 5 : 3
        case .resolution: isWide ? 5 : 3
        case .frameRate: isWide ? 8 : 4
        case .colour: isWide ? 5 : 3
        }
    }

    var title: String {
        switch self {
        case .codec: "Codec"
        case .quality: "Quality"
        case .resolution: "Resolution"
        case .frameRate: "Frame rate"
        case .colour: "Colour"
        }
    }
}
