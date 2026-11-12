import Foundation

/// Which writer-only options this build can record. The phone lists only what its build records.
nonisolated struct WriterSupport: OptionSet, Sendable {
    let rawValue: Int

    /// ProRes in HLG, from 10-bit frames.
    static let proRes = WriterSupport(rawValue: 1 << 0)
    /// ProRes in Rec. 709, from 8-bit frames.
    static let proResSDR = WriterSupport(rawValue: 1 << 1)
    /// The baked Log profile, ProRes and HEVC.
    static let log = WriterSupport(rawValue: 1 << 2)
    static let all: WriterSupport = [.proRes, .proResSDR, .log]

    /// What this build can record. The Simulator records nothing and lists everything. A flag joins the device's set in the task
    /// that makes the recording work.
    static func shipped(isSimulator: Bool) -> WriterSupport {
        isSimulator ? .all : []
    }
}
