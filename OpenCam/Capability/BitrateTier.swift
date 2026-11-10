import Foundation

nonisolated enum BitrateTier: String, Codable, Sendable, Hashable, CaseIterable {
    case max = "Max"
    case high = "High"
    case medium = "Medium"
    case low = "Low"

    var bitsPerPixelPerFrame: Double {
        switch self {
        case .max: 0.18
        case .high: 0.11
        case .medium: 0.07
        case .low: 0.04
        }
    }
}
