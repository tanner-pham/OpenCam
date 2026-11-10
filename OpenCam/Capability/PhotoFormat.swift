import Foundation

nonisolated enum PhotoFormat: String, Codable, Sendable, Hashable, CaseIterable {
    case raw = "RAW"
    case rawPlusHEIF = "RAW + HEIF"
    case heif = "HEIF"

    var includesRAW: Bool {
        switch self {
        case .raw, .rawPlusHEIF: true
        case .heif: false
        }
    }
}
