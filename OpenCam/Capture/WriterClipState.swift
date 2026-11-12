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

    /// Presentation time the baseline looks back over, and room for that many frames at the fastest rate the camera delivers.
    private static let windowSeconds = 1.0
    private static let windowCapacity = 256

    private let policy: DropPolicy
    private let frameSeconds: Double
    private let minFreeBytes: Int64

    private var firstPTS: CMTime?
    private var firstArrival = 0.0
    private var windowOffsets = [Double](repeating: 0, count: WriterClipState.windowCapacity)
    private var windowDelays = [Double](repeating: 0, count: WriterClipState.windowCapacity)
    private var windowStart = 0
    private var windowCount = 0
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
            _ = recordDelay(0, at: 0)
            return .startAndWrite(at: pts)
        }
        let offset = CMTimeGetSeconds(CMTimeSubtract(pts, firstPTS))
        let lag = recordDelay((now - firstArrival) - offset, at: offset)
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

    /// Adds this frame's delivery delay (its arrival offset minus its presentation offset, both from the first frame) to the
    /// ring of the last second of presentation time, and returns how far it is above the smallest delay in that second.
    /// The smallest recent delay is the baseline, so a lasting change in the camera's delay stops counting as lag once the
    /// older, smaller delays have aged out, while a short hiccup is still measured against the steady delay before it.
    /// Skipped frames are recorded too: their delay is real, and without it the baseline could never rise.
    private mutating func recordDelay(_ delay: Double, at offset: Double) -> Double {
        let capacity = Self.windowCapacity
        // Drop what is older than the window (the ring is oldest first from `windowStart`).
        while windowCount > 0, windowOffsets[windowStart] <= offset - Self.windowSeconds {
            windowStart = (windowStart + 1) % capacity
            windowCount -= 1
        }
        if windowCount == capacity {
            windowStart = (windowStart + 1) % capacity
            windowCount -= 1
        }
        let slot = (windowStart + windowCount) % capacity
        windowOffsets[slot] = offset
        windowDelays[slot] = delay
        windowCount += 1
        var smallest = delay
        for step in 0..<windowCount { smallest = min(smallest, windowDelays[(windowStart + step) % capacity]) }
        return delay - smallest
    }

    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) * 1e-18
    }
}
