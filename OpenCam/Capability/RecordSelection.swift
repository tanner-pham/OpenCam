import Foundation

nonisolated struct RecordSelection: Codable, Sendable, Hashable {
    var family: CodecFamily
    var quality: String
    var resolution: Resolution
    var frameRate: Int
    var colour: ColourMode
}
