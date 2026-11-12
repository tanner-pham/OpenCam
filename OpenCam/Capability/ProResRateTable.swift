import Foundation

/// Apple's ProRes target data rates: Apple ProRes White Paper, April 2022, "Target Data Rates", pages 19 to 21
/// (https://www.apple.com/final-cut-pro/docs/Apple_ProRes.pdf), 16:9 rows at 720p, 1080p and 2160p, in Mb/s.
nonisolated enum ProResRateTable {
    private static let frameRates = [24, 25, 30, 50, 60]

    private enum Kind: Int { case proxy, lt, standard, hq }

    /// Pixel count, then the four kinds in `Kind` order, each with a rate per entry of `frameRates`.
    private static let rows: [Int: [[Double]]] = [
        1280 * 720: [
            [18, 19, 23, 38, 45], [41, 42, 51, 84, 101], [59, 61, 73, 122, 147], [88, 92, 110, 184, 220],
        ],
        1920 * 1080: [
            [36, 38, 45, 76, 91], [82, 85, 102, 170, 204], [117, 122, 147, 245, 293], [176, 184, 220, 367, 440],
        ],
        3840 * 2160: [
            [145, 151, 182, 303, 363], [328, 342, 410, 684, 821], [471, 492, 589, 983, 1178], [707, 737, 884, 1475, 1768],
        ],
    ]

    /// Apple's target rate in Mb/s; nil when Apple publishes no row for that kind, size or rate. Width and height in either order.
    static func megabitsPerSecond(quality: String, width: Int, height: Int, frameRate: Int) -> Double? {
        guard let kind = kind(of: quality),
              let kinds = rows[width * height],
              let column = frameRates.firstIndex(of: frameRate) else { return nil }
        return kinds[kind.rawValue][column]
    }

    private static func kind(of quality: String) -> Kind? {
        let name = quality.lowercased()
        if name.contains("4444") || name.contains("xq") { return nil }
        if name.contains("proxy") { return .proxy }
        if name.contains("hq") { return .hq }
        if name.contains("lt") { return .lt }
        if name.contains("422") { return .standard }
        return nil
    }
}
