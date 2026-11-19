import AVFoundation
import Synchronization

/// Collects the photos of one request, measuring each in memory, and delivers once when the capture finishes or `expire` is
/// called. The same shape as `PhotoCaptureDelegate`, which hands its result to a continuation.
nonisolated final class RawSizeCheckDelegate: NSObject, AVCapturePhotoCaptureDelegate, Sendable {
    struct Outcome: Sendable {
        var photos: [RawSizeCheckPhoto] = []
        var rawDimensions: RawSizeCheckSize?
        var photoDimensions: RawSizeCheckSize?
        var error: String?
        var isTimedOut = false
    }

    private struct State {
        var outcome = Outcome()
        var isFinished = false
        var continuation: CheckedContinuation<Outcome, Never>?
    }

    private let state = Mutex(State())

    /// Set before the request is made.
    func deliver(to continuation: CheckedContinuation<Outcome, Never>) {
        state.withLock { $0.continuation = continuation }
    }

    /// The resolved sizes are known when the capture begins, so a capture that later times out still reports them.
    func photoOutput(_ output: AVCapturePhotoOutput, willBeginCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        let raw = Self.nonEmpty(resolvedSettings.rawPhotoDimensions)
        let processed = Self.nonEmpty(resolvedSettings.photoDimensions)
        state.withLock { state in
            state.outcome.rawDimensions = raw ?? state.outcome.rawDimensions
            state.outcome.photoDimensions = processed ?? state.outcome.photoDimensions
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: (any Error)?) {
        if let error {
            state.withLock { $0.outcome.error = $0.outcome.error ?? "Processing failed: \(Self.describe(error))" }
            return
        }
        let resolved = photo.resolvedSettings
        guard let data = photo.fileDataRepresentation() else {
            state.withLock { $0.outcome.error = $0.outcome.error ?? "[RawSizeCheckDelegate:didFinishProcessingPhoto] The photo has no file data — {isRaw: \(photo.isRawPhoto)}" }
            return
        }
        let measured = RawSizeCheckMeasure.photo(isRaw: photo.isRawPhoto, data: data)
        state.withLock { state in
            state.outcome.photos.append(measured)
            state.outcome.rawDimensions = Self.nonEmpty(resolved.rawPhotoDimensions) ?? state.outcome.rawDimensions
            state.outcome.photoDimensions = Self.nonEmpty(resolved.photoDimensions) ?? state.outcome.photoDimensions
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: (any Error)?) {
        let raw = Self.nonEmpty(resolvedSettings.rawPhotoDimensions)
        let processed = Self.nonEmpty(resolvedSettings.photoDimensions)
        finish { outcome in
            outcome.rawDimensions = raw ?? outcome.rawDimensions
            outcome.photoDimensions = processed ?? outcome.photoDimensions
            if let error { outcome.error = outcome.error ?? "Capture failed: \(Self.describe(error))" }
            if outcome.error == nil, outcome.photos.isEmpty { outcome.error = "The capture finished with no photo" }
        }
    }

    /// Ends the request when nothing finished it in time.
    func expire(after limit: Duration) {
        finish { outcome in
            outcome.isTimedOut = true
            outcome.error = outcome.error ?? "Timed out after \(limit)"
        }
    }

    private func finish(_ update: (inout Outcome) -> Void) {
        let delivery = state.withLock { state -> (CheckedContinuation<Outcome, Never>, Outcome)? in
            guard !state.isFinished else { return nil }
            update(&state.outcome)
            state.isFinished = true
            guard let continuation = state.continuation else { return nil }
            state.continuation = nil
            return (continuation, state.outcome)
        }
        if let delivery { delivery.0.resume(returning: delivery.1) }
    }

    private static func nonEmpty(_ dimensions: CMVideoDimensions) -> RawSizeCheckSize? {
        let size = RawSizeCheckSize(dimensions)
        return size.isEmpty ? nil : size
    }

    private static func describe(_ error: any Error) -> String {
        let nsError = error as NSError
        return "domain: \(nsError.domain), code: \(nsError.code), \(nsError.localizedDescription)"
    }
}
