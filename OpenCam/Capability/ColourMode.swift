import Foundation

nonisolated enum ColourMode: String, Codable, Sendable, Hashable, CaseIterable {
    case rec709 = "Rec. 709"
    case p3 = "P3"
    case hlg = "HLG"
    case appleLog = "Apple Log"
    case appleLog2 = "Apple Log 2"

    /// Maps the raw value of a capture colour space (0 sRGB, 1 P3_D65, 2 HLG_BT2020, 3 AppleLog, 4 AppleLog2).
    init?(captureColorSpace rawValue: Int) {
        guard Self.allCases.indices.contains(rawValue) else { return nil }
        self = Self.allCases[rawValue]
    }

    var shortName: String {
        switch self {
        case .rec709: "Rec. 709"
        case .p3: "P3"
        case .hlg: "HLG"
        case .appleLog: "Log"
        case .appleLog2: "Log 2"
        }
    }
}
