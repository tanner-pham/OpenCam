import Foundation
@testable import OpenCam

/// Stands in for `CameraModel` in a sweep. Like the model, it is recording from a clip's start until that clip's result
/// is delivered, and refuses to apply an option meanwhile with `.recordingInProgress`. Options with a codec type in
/// `failingCodecs` cannot be configured; in `hangingCodecs` the clip never reports, so it stays recording; in
/// `hangingApplyCodecs` the configure never returns. Each clip is an empty file whose result reports the requested facts.
@MainActor final class FakeSweepDriver: SweepDriver {
    let directory: URL
    let failingCodecs: Set<String>
    let hangingCodecs: Set<String>
    let hangingApplyCodecs: Set<String>
    weak var sweep: FormatSweep?
    /// Called once a clip has started, so a test can cancel or interrupt mid-clip.
    var onClipStarted: () -> Void = {}
    /// False stands for an interruption or a stopped camera: a clip stopped meanwhile fails at once, as on the device.
    var isCameraUsable = true
    private(set) var applied: [VideoOption] = []
    private(set) var stopCount = 0
    private(set) var isRecording = false
    private var current: VideoOption?
    private var sequence = 0
    private var clipURL: URL?

    init(directory: URL, failingCodecs: Set<String>, hangingCodecs: Set<String> = [], hangingApplyCodecs: Set<String> = []) {
        self.directory = directory
        self.failingCodecs = failingCodecs
        self.hangingCodecs = hangingCodecs
        self.hangingApplyCodecs = hangingApplyCodecs
    }

    func applySweepOption(_ option: VideoOption) async throws(CameraSessionError) {
        guard !isRecording else { throw .recordingInProgress }
        if hangingApplyCodecs.contains(option.codec.codecType) {
            // Longer than any test; the sweep's deadline ends the wait, not this.
            try? await Task.sleep(for: .seconds(600))
        }
        guard !failingCodecs.contains(option.codec.codecType) else { throw .noMatchingFormat(option: option.codec.codecType) }
        applied.append(option)
        current = option
    }

    func beginSweepClip() async -> Bool {
        sequence += 1
        let url = directory.appending(path: CaptureStore.fileName(sequence: sequence, kind: .mov))
        FileManager.default.createFile(atPath: url.path(percentEncoded: false), contents: Data())
        clipURL = url
        isRecording = true
        onClipStarted()
        return true
    }

    func endSweepClip() {
        stopCount += 1
        guard isRecording, let option = current, let url = clipURL, !hangingCodecs.contains(option.codec.codecType) else { return }
        let facts = ClipFacts(codecFourCC: option.codec.codecType, width: option.resolution.width, height: option.resolution.height,
                              nominalFrameRate: Double(option.frameRate), durationSeconds: 3, frameCount: 90, droppedFrames: 0,
                              colour: option.colour, megabitsPerSecond: 100, hasAudio: true)
        let sidecar = ClipSidecar(requested: option, actual: facts, outcome: "completed", recordedAt: Date(), error: nil)
        let result = isCameraUsable
            ? RecordingResult(url: url, option: option, outcome: .completed, sidecar: sidecar)
            : RecordingResult(url: url, option: option, outcome: .stopped(.interrupted, isPlayable: false), sidecar: nil)
        Task {
            isRecording = false
            sweep?.recordingDidFinish(result)
        }
    }
}
