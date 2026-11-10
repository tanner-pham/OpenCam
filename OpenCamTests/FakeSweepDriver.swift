import Foundation
@testable import OpenCam

/// Stands in for `CameraModel` in a sweep: options with a codec type in `failingCodecs` cannot be configured, and each clip
/// is an empty file whose result reports the requested facts and arrives when the clip is stopped.
@MainActor final class FakeSweepDriver: SweepDriver {
    let directory: URL
    let failingCodecs: Set<String>
    weak var sweep: FormatSweep?
    /// Called once a clip has started, so a test can cancel mid-clip.
    var onClipStarted: () -> Void = {}
    private(set) var applied: [VideoOption] = []
    private(set) var stopCount = 0
    private var current: VideoOption?
    private var sequence = 0
    private var clipURL: URL?

    init(directory: URL, failingCodecs: Set<String>) {
        self.directory = directory
        self.failingCodecs = failingCodecs
    }

    func applySweepOption(_ option: VideoOption) async throws(CameraSessionError) {
        guard !failingCodecs.contains(option.codec.codecType) else { throw .noMatchingFormat(option: option.codec.codecType) }
        applied.append(option)
        current = option
    }

    func beginSweepClip() async -> Bool {
        sequence += 1
        let url = directory.appending(path: CaptureStore.fileName(sequence: sequence, kind: .mov))
        FileManager.default.createFile(atPath: url.path(percentEncoded: false), contents: Data())
        clipURL = url
        onClipStarted()
        return true
    }

    func endSweepClip() {
        stopCount += 1
        guard let option = current, let url = clipURL else { return }
        let facts = ClipFacts(codecFourCC: option.codec.codecType, width: option.resolution.width, height: option.resolution.height,
                              nominalFrameRate: Double(option.frameRate), durationSeconds: 3, frameCount: 90, droppedFrames: 0,
                              colour: option.colour, megabitsPerSecond: 100, hasAudio: true)
        let sidecar = ClipSidecar(requested: option, actual: facts, outcome: "completed", recordedAt: Date(), error: nil)
        let result = RecordingResult(url: url, option: option, outcome: .completed, sidecar: sidecar)
        Task { sweep?.recordingDidFinish(result) }
    }
}
