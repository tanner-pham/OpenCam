import Foundation

/// The frame rates the app offers, and how a device's frame-rate ranges map onto them.
nonisolated enum StandardFrameRates {
    static let all = [24, 25, 30, 48, 50, 60, 100, 120]

    /// Rates within 0.05 of some range are kept, so 23.976...29.97 offers 24, 25 and 30.
    static func collapse(_ ranges: [ClosedRange<Double>]) -> [Int] {
        all.filter { rate in
            let value = Double(rate)
            return ranges.contains { $0.lowerBound - 0.05 <= value && value <= $0.upperBound + 0.05 }
        }
    }
}
