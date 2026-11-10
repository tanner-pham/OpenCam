import Foundation

nonisolated struct VideoOption: Codable, Sendable, Hashable {
    let lensID: String
    let codec: VideoCodec
    let resolution: Resolution
    let frameRate: Int
    let colour: ColourMode
}
