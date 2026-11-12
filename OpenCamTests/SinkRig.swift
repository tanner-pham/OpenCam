import AVFoundation
import CoreMedia
import Foundation
import Synchronization
@testable import OpenCam

/// A `WriterSink` on its own writer queue in a temporary folder, fed with synthetic frames. The rig tries ProRes 422 Proxy first and
/// falls back to H.264 when the writer refuses ProRes where the tests run; `codecType` says which one was used.
final class SinkRig {
    /// Totals the sink reported, from any thread.
    nonisolated final class DropLog: Sendable {
        private let values = Mutex<[Int]>([])
        var totals: [Int] { values.withLock { $0 } }
        func append(_ total: Int) { values.withLock { $0.append(total) } }
    }

    let url: URL
    let queue = DispatchSerialQueue(label: "opencam.test.writer")
    let finished = CallCounter()
    let drops = DropLog()
    let sink: WriterSink
    private(set) var codecType = ""
    /// Why each earlier attempt was refused, when the clip was opened for a later codec.
    private(set) var refusals: [String] = []

    init(fileName: String = "OC_0001.MOV") throws {
        url = try TestFiles.directory().appending(path: fileName)
        let finished = finished, drops = drops
        sink = WriterSink(writerQueue: queue, onDrops: { drops.append($0) }, onFinished: { finished.increment() })
    }

    static func proResProxy() -> VideoOption {
        VideoOption(lensID: "w", codec: VideoCodec(family: .proRes, quality: "422 Proxy", codecType: "apco", bitrateTier: nil),
                    resolution: Resolution.named(width: SyntheticFrames.width, height: SyntheticFrames.height), frameRate: SyntheticFrames.framesPerSecond, colour: .rec709)
    }

    static func h264() -> VideoOption {
        VideoOption(lensID: "w", codec: VideoCodec(family: .h264, quality: "Standard", codecType: "avc1", bitrateTier: nil),
                    resolution: Resolution.named(width: SyntheticFrames.width, height: SyntheticFrames.height), frameRate: SyntheticFrames.framesPerSecond, colour: .rec709)
    }

    /// Opens the writer. Returns the option the clip was opened for; throws what the last attempt threw.
    @discardableResult
    func open(policy: DropPolicy = .keepRecording, recordsSound: Bool = false, minFreeBytes: Int64 = 0, audioSettings: [String: Any]? = nil) throws -> VideoOption {
        var lastError: RecordingError?
        for option in [Self.proResProxy(), Self.h264()] {
            let plan = WriterClipPlan.make(option: option, url: url, bufferWidth: SyntheticFrames.width, bufferHeight: SyntheticFrames.height,
                                           rotationDegrees: 0, policy: policy, minFreeBytes: minFreeBytes)
            do {
                let opening: any WriterOpening = sink
                try queue.sync {
                    sink.recommend(video: nil, audio: audioSettings)
                    try opening.open(plan, recordsSound: recordsSound)
                }
                codecType = plan.codecType
                return option
            } catch let error as RecordingError {
                lastError = error
                refusals.append(error.description)
                try? FileManager.default.removeItem(at: url)
            }
        }
        throw lastError ?? RecordingError.writerNotAttached
    }

    /// Delivers frames `range` as a camera at 30 fps would: one every 1/30 s, so the writer keeps up as it does on the phone.
    func deliver(frames range: Range<Int>) async throws {
        for index in range {
            let buffer = try SyntheticFrames.frame(index)
            let arrival = Duration.seconds(Double(index) / Double(SyntheticFrames.framesPerSecond))
            queue.sync { sink.receiveVideo(buffer, arrival: arrival) }
            try await Task.sleep(for: .milliseconds(33))
        }
    }

    /// Frame `index` then the sound that starts with it, one pair every 1/30 s, as the two outputs would interleave.
    func deliverInterleaved(frames range: Range<Int>) async throws {
        for index in range {
            let frame = try SyntheticFrames.frame(index)
            let sound = try SyntheticFrames.sound(startingAtFrame: index)
            let arrival = Duration.seconds(Double(index) / Double(SyntheticFrames.framesPerSecond))
            queue.sync { sink.receiveVideo(frame, arrival: arrival) }
            queue.sync { sink.receiveAudio(sound) }
            try await Task.sleep(for: .milliseconds(33))
        }
    }

    func deliverSound(frames range: Range<Int>) async throws {
        for index in range {
            let buffer = try SyntheticFrames.sound(startingAtFrame: index)
            queue.sync { sink.receiveAudio(buffer) }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    func end(_ end: WriterEnd) -> Bool { queue.sync { sink.end(end) } }
    func drop(_ reason: DropReason, atFrame index: Int) {
        let arrival = Duration.seconds(Double(index) / Double(SyntheticFrames.framesPerSecond))
        queue.sync { sink.receiveDrop(reason, arrival: arrival) }
    }
    func takeReport(timedOut: Bool = false) -> WriterReport? { queue.sync { sink.takeReport(timedOut: timedOut) } }

    /// Waits up to ten seconds for the sink to say it finished `count` times.
    func waitForFinishes(_ count: Int = 1) async -> Bool {
        for _ in 0..<1_000 {
            if finished.value >= count { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return finished.value >= count
    }
}
