import Foundation

extension CameraModel {
    /// The "When frames drop" row: two chips, the saved policy selected, and the line for the recorder the selection uses.
    var dropChoice: DropChoice {
        DropChoice(chips: DropPolicy.allCases.map { Chip(id: $0.rawValue, title: $0.title, detail: nil, isAvailable: true, reason: nil) },
                   selectedID: dropPolicy.rawValue,
                   reason: DropPolicy.line(dropPolicy, recorder: recorderPath)) { [weak self] id in
            guard let policy = DropPolicy(rawValue: id) else { return }
            self?.dropPolicy = policy
        }
    }

    /// While a writer clip records, holds background time until its result arrives (or the time runs out), so the clip can be
    /// finished and saved. It never stops the clip: the session's interruption does, with `.interrupted`. One claim per clip.
    func appEnteredBackground() {
        guard isRecording, recordingClip != nil, recorderPath == .writer, backgroundWork == nil else { return }
        backgroundWork = beginBackgroundWork("OpenCam clip")
    }

    /// The clip's result arrived.
    func endBackgroundWork() {
        backgroundWork?.end()
        backgroundWork = nil
    }
}
