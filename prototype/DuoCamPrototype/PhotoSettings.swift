import Foundation

struct PhotoSettings: Equatable {
    var format = "RAW + HEIF"
    var resolution = "48 MP"
    var lens = "1x"

    static let formats = ["RAW + HEIF", "RAW", "HEIF"]
    static let resolutions = ["12 MP", "48 MP"]
    static let lenses = ["0.5x", "1x", "2x"]

    var summaryParts: [String] { [format, resolution] }
}
