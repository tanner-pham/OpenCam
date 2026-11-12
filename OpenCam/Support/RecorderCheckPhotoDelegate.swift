import AVFoundation
import Synchronization

/// Times one RAW photo request: the moment it was made, when the RAW photo was processed, when the capture finished. The DNG
/// is written to the temporary directory and deleted at once; its size and the write time are kept.
nonisolated final class RecorderCheckPhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate, Sendable {
    private struct State {
        var shot: RecorderCheckPhotoShot
        var requestedAt: ContinuousClock.Instant?
        var isFinished = false
        var continuation: CheckedContinuation<RecorderCheckPhotoShot, Never>?
    }

    private let state: Mutex<State>
    private let runStart: ContinuousClock.Instant
    private let fileURL: URL

    init(index: Int, runStart: ContinuousClock.Instant, fileURL: URL) {
        self.runStart = runStart
        self.fileURL = fileURL
        state = Mutex(State(shot: RecorderCheckPhotoShot(index: index, requestedAtMilliseconds: 0)))
        super.init()
    }

    /// Called just before the request is made.
    func markRequested() {
        let now = ContinuousClock.now
        state.withLock { state in
            state.requestedAt = now
            state.shot.requestedAtMilliseconds = (now - runStart).recorderCheckMilliseconds
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: (any Error)?) {
        let now = ContinuousClock.now
        state.withLock { state in
            guard let requestedAt = state.requestedAt, state.shot.requestToProcessedMilliseconds == nil else { return }
            state.shot.requestToProcessedMilliseconds = (now - requestedAt).recorderCheckMilliseconds
        }
        if let error {
            state.withLock { $0.shot.error = $0.shot.error ?? "Processing failed: \(error.localizedDescription)" }
            return
        }
        guard let data = photo.fileDataRepresentation() else {
            state.withLock { $0.shot.error = $0.shot.error ?? "The photo has no file data" }
            return
        }
        let writeStart = ContinuousClock.now
        let writeError: String?
        do {
            try data.write(to: fileURL, options: .atomic)
            writeError = nil
        } catch {
            writeError = "The DNG could not be written: \(error.localizedDescription)"
        }
        let written = ContinuousClock.now - writeStart
        try? FileManager.default.removeItem(at: fileURL)
        state.withLock { state in
            state.shot.dngBytes = data.count
            state.shot.writeMilliseconds = written.recorderCheckMilliseconds
            state.shot.error = state.shot.error ?? writeError
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: (any Error)?) {
        let now = ContinuousClock.now
        finish { state in
            if let requestedAt = state.requestedAt { state.shot.requestToCaptureFinishedMilliseconds = (now - requestedAt).recorderCheckMilliseconds }
            if let error { state.shot.error = state.shot.error ?? "Capture failed: \(error.localizedDescription)" }
            if state.shot.error == nil, state.shot.dngBytes == nil { state.shot.error = "The capture finished with no RAW photo" }
        }
    }

    /// Ends the request with an error when nothing finished it in time.
    func expire(after limit: Duration) {
        finish { state in
            state.shot.error = state.shot.error ?? "Timed out after \(limit)"
        }
    }

    /// The finished shot; waits until the capture finishes or `expire` is called.
    func result() async -> RecorderCheckPhotoShot {
        await withCheckedContinuation { (continuation: CheckedContinuation<RecorderCheckPhotoShot, Never>) in
            let ready = state.withLock { state -> RecorderCheckPhotoShot? in
                if state.isFinished { return state.shot }
                state.continuation = continuation
                return nil
            }
            if let ready { continuation.resume(returning: ready) }
        }
    }

    private func finish(_ update: (inout State) -> Void) {
        let delivery = state.withLock { state -> (CheckedContinuation<RecorderCheckPhotoShot, Never>, RecorderCheckPhotoShot)? in
            guard !state.isFinished else { return nil }
            update(&state)
            state.isFinished = true
            guard let continuation = state.continuation else { return nil }
            state.continuation = nil
            return (continuation, state.shot)
        }
        if let delivery { delivery.0.resume(returning: delivery.1) }
    }
}
