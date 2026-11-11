import Foundation

/// Times main-actor work for the performance tests: the median of several runs, printed as `[perf] name: 1.234 ms`.
/// The numbers are relative (a Debug Simulator build); the tests that print them assert only generous bounds.
enum PerfClock {
    static func median(runs: Int = 7, _ body: () throws -> Void) rethrows -> Duration {
        let clock = ContinuousClock()
        var samples: [Duration] = []
        for _ in 0..<runs {
            samples.append(try clock.measure(body))
        }
        return samples.sorted()[runs / 2]
    }

    /// Times `body` and prints the median.
    @discardableResult
    static func report(_ name: String, runs: Int = 7, _ body: () throws -> Void) rethrows -> Duration {
        let duration = try median(runs: runs, body)
        print("[perf] \(name): \(milliseconds(duration)) ms")
        return duration
    }

    static func milliseconds(_ duration: Duration) -> String {
        let (seconds, attoseconds) = duration.components
        return String(format: "%.3f", Double(seconds) * 1_000 + Double(attoseconds) / 1e15)
    }
}
