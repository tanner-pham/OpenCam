import Foundation

nonisolated struct PhotoOption: Codable, Sendable, Hashable {
    let lensID: String
    let format: PhotoFormat
    let width: Int
    let height: Int

    var megapixels: Int { width * height / 1_000_000 }
    var label: String { "\(megapixels) MP" }
}
