import Darwin
import Foundation

/// When each launch phase finished, counted from the process start, for one `[timing] launch ...` journal line per launch:
/// `[timing] launch model 140 ms, start 210 ms, access 215 ms, lenses 250 ms, cache 300 ms, capabilities 310 ms, configured 320 ms, running 1290 ms`.
/// Notes (`note`) sit among the marks in order.
nonisolated struct LaunchTimeline: Sendable {
    let processStart: Date
    private(set) var phases: [String] = []

    init(processStart: Date = LaunchTimeline.processStartDate() ?? .now) {
        self.processStart = processStart
    }

    /// Notes that `phase` finished now.
    mutating func mark(_ phase: String, at date: Date = .now) {
        phases.append("\(phase) \(Int((date.timeIntervalSince(processStart) * 1_000).rounded())) ms")
    }

    /// Appends `text` as written, in order with the marks.
    mutating func note(_ text: String) {
        phases.append(text)
    }

    var line: String { "[timing] launch " + phases.joined(separator: ", ") }

    /// The kernel's record of when this process started; nil if it cannot be read.
    static func processStartDate() -> Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&name, u_int(name.count), &info, &size, nil, 0) == 0 else { return nil }
        let start = info.kp_proc.p_starttime
        return Date(timeIntervalSince1970: Double(start.tv_sec) + Double(start.tv_usec) / 1_000_000)
    }
}
