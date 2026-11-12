import Foundation

nonisolated struct Resolution: Codable, Sendable, Hashable {
    let width: Int
    let height: Int
    let label: String

    var id: String { "\(width)x\(height)" }
    var detail: String { "\(width) × \(height)" }
    var pixelCount: Int { width * height }

    static func named(width: Int, height: Int) -> Resolution {
        let label: String
        switch (width, height) {
        case (3840, 2160): label = "4K"
        case (4096, 2160): label = "4K DCI"
        case (2704, 1520): label = "2.7K"
        case (1920, 1080): label = "1080p"
        case (1280, 720): label = "720p"
        case _ where width * 3 == height * 4: label = "Open gate"
        default: label = "\(width) × \(height)"
        }
        return Resolution(width: width, height: height, label: label)
    }
}
