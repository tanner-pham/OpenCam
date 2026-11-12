import CoreMedia
import Foundation

/// Every decision a writer clip makes: its first frame, its drops, the stop policy and how it ends. A value with no clock
/// and no writer, so it is tested with synthetic timing. The sink calls it only on its own serial queue.
nonisolated struct WriterClipState: Sendable {
    enum VideoStep: Sendable, Equatable {
        /// Start the writer's session at this time, then append the frame.
        case startAndWrite(at: CMTime)
        case write
        /// The frame is not rendered and not written; the drop is already counted.
        case skip
        /// The clip has ended.
        case ignore
    }

    enum Finish: Sendable, Equatable {
        /// End the session at this time and finish writing.
        case finish(endTime: CMTime)
        /// Nothing was written: cancel.
        case cancel
        /// The clip had already ended.
        case none
    }

    private static let reportInterval = 0.25
    /// Absorbs the rounding of converting a duration to seconds, so a lag of exactly one frame is not behind.
    private static let lagTolerance = 1e-9

    private let policy: DropPolicy
    private let frameSeconds: Double
    private let minFreeBytes: Int64

    private var firstPTS: CMTime?
    private var firstArrival = 0.0
    private var lastWrittenEnd: CMTime?
    private var pendingFinish: Finish?
    private var lastReportArrival: Double?
    private var lastReportedTotal = 0

    private(set) var end: WriterEnd?
    private(set) var facts = DropFacts()

    init(policy: DropPolicy, frameDuration: CMTime, minFreeBytes: Int64) {
        self.policy = policy
        frameSeconds = CMTimeGetSeconds(frameDuration)
        self.minFreeBytes = minFreeBytes
    }

    var isInFlight: Bool { end == nil }

    /// A video frame arrived. `arrival` is the time since the clip opened, on the sink's own clock.
    /// A `.skip` may have ended the clip (policy "Stop recording"): call `takePendingFinish()` after it.
    mutating func video(pts: CMTime, duration: CMTime, arrival: Duration, isWriterReady: Bool) -> VideoStep {
        guard end == nil else { return .ignore }
        facts.framesDelivered += 1
        let now = Self.seconds(arrival)
        guard let firstPTS else {
            guard isWriterReady else {
                countDrop(.writerNotReady)
                return .skip
            }
            self.firstPTS = pts
            firstArrival = now
            return .startAndWrite(at: pts)
        }
        let lag = (now - firstArrival) - CMTimeGetSeconds(CMTimeSubtract(pts, firstPTS))
        if lag > frameSeconds + Self.lagTolerance {
            countDrop(.behind)
            return .skip
        }
        guard isWriterReady else {
            countDrop(.writerNotReady)
            return .skip
        }
        return .write
    }

    /// The append result. A frame that was not written ends the clip as `.writerFailed`.
    mutating func videoWritten(_ isWritten: Bool, pts: CMTime, duration: CMTime) -> Finish {
        guard isWritten else { return end(.writerFailed) }
        guard end == nil else { return .none }
        facts.framesWritten += 1
        lastWrittenEnd = CMTimeAdd(pts, duration)
        return .none
    }

    /// The output's drop callback.
    mutating func outputDropped(_ reason: DropReason) -> Finish {
        countDrop(reason)
        return takePendingFinish()
    }

    mutating func renderFailed() -> Finish {
        countDrop(.renderFailed)
        return takePendingFinish()
    }

    /// Whether to append this sound buffer. Sound before the first video frame is not written and is not a drop.
    mutating func audio(pts: CMTime, isWriterReady: Bool) -> Bool {
        guard end == nil, let firstPTS, CMTimeCompare(pts, firstPTS) >= 0 else { return false }
        guard isWriterReady else {
            facts.audioBuffersNotWritten += 1
            return false
        }
        return true
    }

    mutating func storage(freeBytes: Int64) -> Finish {
        freeBytes <= minFreeBytes ? end(.storageFull) : .none
    }

    /// The first end stands; a later one does nothing.
    mutating func end(_ reason: WriterEnd) -> Finish {
        guard end == nil else { return .none }
        end = reason
        guard let lastWrittenEnd else { return .cancel }
        return .finish(endTime: lastWrittenEnd)
    }

    /// The end a drop found inside `video` caused, handed over once.
    mutating func takePendingFinish() -> Finish {
        defer { pendingFinish = nil }
        return pendingFinish ?? .none
    }

    /// The total to show: at the first drop, then at most once per 250 ms of `arrival`, and only when it changed.
    mutating func dropCountToReport(arrival: Duration) -> Int? {
        guard facts.total > 0, facts.total != lastReportedTotal else { return nil }
        let now = Self.seconds(arrival)
        if let lastReportArrival, now - lastReportArrival < Self.reportInterval { return nil }
        lastReportArrival = now
        lastReportedTotal = facts.total
        return facts.total
    }

    private mutating func countDrop(_ reason: DropReason) {
        guard end == nil else { return }
        facts.total += 1
        facts.byReason[reason.rawValue, default: 0] += 1
        guard policy == .stopRecording, lastWrittenEnd != nil else { return }
        facts.stoppedRecording = true
        pendingFinish = end(.droppedFrames)
    }

    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) * 1e-18
    }
}
