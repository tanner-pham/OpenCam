import AVFoundation

/// Reads a finished clip back to record what it actually contains.
nonisolated enum ClipInspector {
    /// Samples stepped per cursor call while counting frames.
    private static let stepChunk: Int64 = 1024

    static func inspect(url: URL, requestedFrameRate: Int) async throws(RecordingError) -> ClipFacts {
        let path = url.path(percentEncoded: false)
        let asset = AVURLAsset(url: url)
        do {
            guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                throw RecordingError.noVideoTrack(path: path)
            }
            let (formats, nominalFrameRate, timeRange, dataRate, canCount) = try await track.load(
                .formatDescriptions, .nominalFrameRate, .timeRange, .estimatedDataRate, .canProvideSampleCursors)
            guard let format = formats.first else { throw RecordingError.noVideoTrack(path: path) }
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            let duration = timeRange.duration.seconds
            let frameCount = canCount ? countFrames(track) : 0
            let dimensions = CMVideoFormatDescriptionGetDimensions(format)
            return ClipFacts(
                codecFourCC: fourCC(CMFormatDescriptionGetMediaSubType(format)),
                width: Int(dimensions.width),
                height: Int(dimensions.height),
                nominalFrameRate: Double(nominalFrameRate),
                durationSeconds: duration,
                frameCount: frameCount,
                droppedFrames: droppedFrames(durationSeconds: duration, frameRate: requestedFrameRate, frameCount: frameCount),
                colour: colour(primaries: extensionString(format, kCMFormatDescriptionExtension_ColorPrimaries),
                               transfer: extensionString(format, kCMFormatDescriptionExtension_TransferFunction),
                               log: extensionString(format, kCMFormatDescriptionExtension_LogTransferFunction)),
                megabitsPerSecond: Double(dataRate) / 1e6,
                hasAudio: !audioTracks.isEmpty
            )
        } catch let error as RecordingError {
            throw error
        } catch {
            throw .cannotInspect(path: path, reason: error.localizedDescription)
        }
    }

    /// The frames the requested rate implies for the duration, minus the frames present; never negative.
    static func droppedFrames(durationSeconds: Double, frameRate: Int, frameCount: Int) -> Int {
        guard durationSeconds.isFinite, durationSeconds > 0 else { return 0 }
        let expected = Int((durationSeconds * Double(frameRate)).rounded())
        return max(0, expected - frameCount)
    }

    /// Log transfer first (Apple Log 2, Apple Log), then HLG, then P3 primaries, then Rec. 709 primaries and transfer.
    static func colour(primaries: String?, transfer: String?, log: String?) -> ColourMode? {
        if log == kCMFormatDescriptionLogTransferFunction_AppleLog2 as String { return .appleLog2 }
        if log == kCMFormatDescriptionLogTransferFunction_AppleLog as String { return .appleLog }
        if transfer == kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String { return .hlg }
        if primaries == kCMFormatDescriptionColorPrimaries_P3_D65 as String { return .p3 }
        if primaries == kCMFormatDescriptionColorPrimaries_ITU_R_709_2 as String,
           transfer == kCMFormatDescriptionTransferFunction_ITU_R_709_2 as String { return .rec709 }
        return nil
    }

    /// Steps a sample cursor from the first sample to the last in decode order.
    private static func countFrames(_ track: AVAssetTrack) -> Int {
        guard let cursor = track.makeSampleCursorAtFirstSampleInDecodeOrder() else { return 0 }
        var count: Int64 = 1
        while true {
            let stepped = cursor.stepInDecodeOrder(byCount: stepChunk)
            count += stepped
            if stepped < stepChunk { break }
        }
        return Int(count)
    }

    private static func extensionString(_ format: CMFormatDescription, _ key: CFString) -> String? {
        CMFormatDescriptionGetExtension(format, extensionKey: key) as? String
    }

    private static func fourCC(_ code: FourCharCode) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: code >> $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
