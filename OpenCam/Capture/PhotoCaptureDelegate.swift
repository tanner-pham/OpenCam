import AVFoundation
import Synchronization

/// Writes each photo of one request to its file as it arrives, and reports every file written once the capture
/// finishes. RAW and processed photos arrive as separate callbacks (AVCapturePhotoOutput.h, `isRawPhoto`).
nonisolated final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate, Sendable {
    typealias Outcome = Result<[URL], PhotoCaptureError>

    private struct State {
        var continuation: CheckedContinuation<Outcome, Never>?
        var saved: [URL] = []
        var failure: PhotoCaptureError?
    }

    private let dngURL: URL
    private let heicURL: URL
    private let state = Mutex(State())

    init(dngURL: URL, heicURL: URL) {
        self.dngURL = dngURL
        self.heicURL = heicURL
    }

    /// Set before the request is made; the outcome is delivered once, when the capture finishes.
    func deliver(to continuation: CheckedContinuation<Outcome, Never>) {
        state.withLock { $0.continuation = continuation }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: (any Error)?) {
        let result = save(photo, error: error)
        state.withLock { state in
            switch result {
            case .success(let url): state.saved.append(url)
            case .failure(let failure): state.failure = state.failure ?? failure
            }
        }
    }

    /// The last callback of every request, also after a failure.
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: (any Error)?) {
        let finished = state.withLock { state -> (CheckedContinuation<Outcome, Never>?, Outcome) in
            let continuation = state.continuation
            state.continuation = nil
            if let failure = state.failure ?? error.map({ PhotoCaptureError.captureFailed(reason: Self.describe($0)) }) {
                return (continuation, .failure(failure))
            }
            return (continuation, state.saved.isEmpty ? .failure(.noPhotoData) : .success(state.saved))
        }
        finished.0?.resume(returning: finished.1)
    }

    private func save(_ photo: AVCapturePhoto, error: (any Error)?) -> Result<URL, PhotoCaptureError> {
        if let error { return .failure(.captureFailed(reason: Self.describe(error))) }
        guard let data = photo.fileDataRepresentation() else { return .failure(.noPhotoData) }
        let url = photo.isRawPhoto ? dngURL : heicURL
        do {
            try data.write(to: url, options: .withoutOverwriting)
        } catch {
            return .failure(.writeFailed(path: url.lastPathComponent, reason: error.localizedDescription))
        }
        return .success(url)
    }

    private static func describe(_ error: any Error) -> String {
        let nsError = error as NSError
        return "domain: \(nsError.domain), code: \(nsError.code), \(nsError.localizedDescription)"
    }
}
