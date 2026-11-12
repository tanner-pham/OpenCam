import AVFoundation
import CoreVideo
import Foundation
import Testing
@testable import OpenCam

@Suite struct WriterRecorderTests {
    func recorder() -> WriterRecorder {
        let (_, results) = AsyncStream.makeStream(of: RecordingResult.self)
        let (_, events) = AsyncStream.makeStream(of: SessionEvent.self)
        return WriterRecorder(results: results, events: events, onFinished: {})
    }

    @Test func theColourPicksThePixelFormat() {
        #expect(WriterRecorder.pixelFormat(for: .hlg) == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange)
        #expect(WriterRecorder.pixelFormat(for: .log) == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange)
        #expect(WriterRecorder.pixelFormat(for: .rec709) == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
        #expect(WriterRecorder.pixelFormat(for: .p3) == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
        #expect(WriterRecorder.pixelFormat(for: .appleLog) == nil)
        #expect(WriterRecorder.pixelFormat(for: .appleLog2) == nil)
    }

    @Test func aNewRecorderHasNoClipAndNothingToStop() {
        let writer = recorder()
        #expect(!writer.isClipInFlight)
        #expect(!writer.hasResultPending)
        #expect(!writer.end(.user))
        #expect(writer.audioLevels().isEmpty)
        writer.collect()
        writer.collect(timedOut: true)
        #expect(!writer.isClipInFlight)
    }

    @Test func theVideoOutputIsFullSizeAndKeepsLateFrames() {
        let writer = recorder()
        #expect(!writer.videoOutput.alwaysDiscardsLateVideoFrames)
        #expect(!writer.videoOutput.automaticallyConfiguresOutputBufferDimensions)
        #expect(!writer.videoOutput.deliversPreviewSizedOutputBuffers)
    }

    @Test func aPixelFormatTheOutputDoesNotOfferIsRefused() {
        // Nothing is attached, so the output offers nothing to ask for.
        #expect(!recorder().preparePixelFormat(for: .hlg))
        #expect(!recorder().preparePixelFormat(for: .appleLog2))
    }
}
