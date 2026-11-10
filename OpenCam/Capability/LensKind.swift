import Foundation

nonisolated enum LensKind: String, Codable, Sendable, Hashable {
    case ultraWide
    case wide
    case outerUltraWide
    case innerUltraWide
}
