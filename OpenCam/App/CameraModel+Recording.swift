import Foundation

extension CameraModel {
    /// Reserves a file number and starts recording behind any queued configure. `isRecording` holds from the press,
    /// so lens, mode and format stay as they are until `recordingDidFinish`. Returns the start, which ends once the clip is
    /// recording or `recordingDidFinish` has reported its failure; nil when nothing started and no result will follow.
    @discardableResult
    func startRecording() -> Task<Void, Never>? {
        guard let configurator, let option = currentVideoOption,
              let store = store(failureNotice: RecordingOutcome.failedNotice) else { return nil }
        let url = store.url(sequence: store.reserveSequence(), kind: .mov)
        let isSweepClip = isSweeping
        if isSweepClip { recordSweepClip(url) }
        let minFreeBytes = recordingReserveBytes()
        let pendingConfigure = configureTask
        isRecording = true
        recordingClip = (url, option)
        resetDroppedFrames()
        let dropPolicy = dropPolicy
        let task = Task {
            if let configureError = await pendingConfigure?.value {
                // The session went back to its last working format, which is not the one the press was for.
                recordingDidFinish(RecordingResult(url: url, option: option, outcome: .failed(configureError.description), sidecar: nil))
                return
            }
            do throws(RecordingError) {
                try await configurator.startRecording(option: option, url: url, minFreeBytes: minFreeBytes, dropPolicy: dropPolicy)
                // A clip that ended as it started has already reported; the idle timecode must not keep a start time.
                guard isRecording, let recordingClip, CaptureStore.clipKey(for: recordingClip.url) == CaptureStore.clipKey(for: url) else { return }
                recordingStart = Date()
                recordingBegan(isSweepClip: isSweepClip)
            } catch {
                recordingDidFinish(RecordingResult(url: url, option: option, outcome: .failed(error.description), sidecar: nil))
            }
        }
        recordingStartTask = task
        return task
    }

    /// Waits for a recording that is still starting, then stops it; the UI resets in `recordingDidFinish`. When the session
    /// had no clip in flight, no result will come, so the clip is ended here.
    func stopRecording() {
        guard let configurator else { return }
        let start = recordingStartTask
        let clip = recordingClip?.url
        Task {
            await start?.value
            let isClipInFlight = await configurator.stopRecording()
            guard !isClipInFlight, let clip else { return }
            endRecordingWithoutResult(clip: clip, context: "stopRecording")
        }
    }

    /// Ends the recording when its result will never arrive: through `recordingDidFinish`, as `.failed` when no file
    /// exists and as `.stopped(.noResult)` when one does, which is never reported lost. `clip` nil ends whichever clip is
    /// recording; otherwise only that clip, and nothing once its result has arrived. A recording with no known clip
    /// (a scripted launch) only resets.
    func endRecordingWithoutResult(clip: URL?, context: String) {
        guard isRecording else { return }
        guard let recordingClip else {
            isRecording = false
            recordingStart = nil
            recordingStartTask = nil
            return
        }
        guard clip.map({ CaptureStore.clipKey(for: $0) == CaptureStore.clipKey(for: recordingClip.url) }) ?? true else { return }
        let path = recordingClip.url.path(percentEncoded: false)
        let message = "[CameraModel:\(context)] No recording result arrived — {path: \(path)}"
        let outcome: RecordingOutcome
        if FileManager.default.fileExists(atPath: path) {
            Self.logger.error("\(message, privacy: .public)")
            outcome = .stopped(.noResult, isPlayable: false)
        } else {
            outcome = .failed(message)
        }
        recordingDidFinish(RecordingResult(url: recordingClip.url, option: recordingClip.option, outcome: outcome, sidecar: nil))
        unreportedClips.insert(CaptureStore.clipKey(for: recordingClip.url))
    }

    /// The free space at which recording stops: the 2 GB reserve, or free space minus the `-freeSpaceMarginMB` margin.
    private func recordingReserveBytes() -> Int64 {
        guard let freeSpaceMarginMB else { return DataRateEstimator.reserveBytes }
        return max(0, FreeSpace.availableBytes() - Int64(freeSpaceMarginMB) * 1_000_000)
    }

    func followRecordings(of session: CameraSession) async {
        for await result in session.recordings {
            recordingDidFinish(result)
        }
    }

    /// Resets the record button and timecode, keeps a playable clip as the last capture, and says what happened:
    /// the outcome's notice, else dropped frames, else nothing (clearing an earlier recording notice).
    /// A selection change held back while recording is applied now, then a recovery held back by a runtime error runs.
    /// During a sweep the result goes to the sweep instead, which reports it in its own rows and drives the next configure.
    /// A sweep clip whose result arrives after the sweep ended never becomes the last capture or a notice, and is deleted
    /// unless `-keepSweepClips on` (its sidecar stays).
    /// A result for a clip the model already ended without one changes no recording state, which may belong to a newer clip.
    func recordingDidFinish(_ result: RecordingResult) {
        if unreportedClips.remove(CaptureStore.clipKey(for: result.url)) == nil {
            endBackgroundWork()
            isRecording = false
            recordingStart = nil
            recordingStartTask = nil
            recordingClip = nil
            recordingEnded()
        }
        if case .failed(let message) = result.outcome {
            Self.logger.error("\(message, privacy: .public)")
        }
        let isSweepClip = sweepClips.remove(CaptureStore.clipKey(for: result.url)) != nil
        if isSweeping, let sweep {
            refreshFreeBytes()
            sweep.recordingDidFinish(result)
            return
        }
        if isSweepClip {
            if !keepsSweepClips { FormatSweep.removeClip(at: result.url) }
            refreshFreeBytes()
            enqueueConfigure()
            resumeDeferredRecovery()
            return
        }
        if result.outcome.isPlayable { captureSaved(result.url) }
        let clipName = result.url.deletingPathExtension().lastPathComponent
        // The writer's own count when the clip has one, else the count read from the file; an unknown count gives no notice.
        let recordingNotice = result.outcome.notice ?? (result.sidecar?.drops?.total ?? result.sidecar?.actual?.droppedFrames).flatMap {
            RecordingOutcome.droppedFramesNotice(clipName: clipName, droppedFrames: $0)
        }
        if let recordingNotice {
            show(recordingNotice, from: .capture)
        } else {
            clearNotice(from: .capture)
        }
        refreshFreeBytes()
        enqueueConfigure()
        // A runtime error during the clip stopped the camera; it recovers now that the clip has ended.
        resumeDeferredRecovery()
    }
}
