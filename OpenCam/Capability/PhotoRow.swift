import Foundation

nonisolated enum PhotoRow: CaseIterable, Sendable {
    case format, resolution

    var title: String {
        switch self {
        case .format: "Format"
        case .resolution: "Resolution"
        }
    }
}
