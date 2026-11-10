import Foundation

nonisolated struct PhotoSelection: Codable, Sendable, Hashable {
    var format: PhotoFormat
    var megapixels: Int
}
