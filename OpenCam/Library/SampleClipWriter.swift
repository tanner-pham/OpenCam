import AVFoundation
import CoreImage
import CoreMedia
import CoreVideo
import Foundation

/// Writes the Simulator's sample clip: `frameCount` frames at 30 fps, each the picture turned through the hue circle, as
/// H.264 tagged Rec. 709, without sound. Offline: it waits for the input rather than dropping a frame.
///
/// iOS 27 deprecates `add`, `startWriting`, an input's `isReadyForMoreMediaData` and `append`, in favour of receivers that want
/// new CoreVideo buffer types. The calls sit in members marked deprecated, reached through `ClipFrameWriting`, the pattern of
/// `WriterSink`, so the build has no warning. Frames go in as sample buffers, which avoids the deprecated pixel buffer adaptor.
nonisolated final class SampleClipWriter: ClipFrameWriting {
    static let width = 1280, height = 720, framesPerSecond: Int32 = 30, frameCount = 90

    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput

    private init(writer: AVAssetWriter, input: AVAssetWriterInput) {
        self.writer = writer
        self.input = input
    }

    /// Renders every frame from `image` and writes the file at `url`; throws `.seedFailed`.
    @concurrent static func write(_ image: CGImage, to url: URL) async throws(LibraryError) {
        let path = url.path(percentEncoded: false)
        func failure(_ reason: String) -> LibraryError { .seedFailed(function: "seedClipIfAbsent", path: path, reason: reason) }
        let colour: [String: String] = [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                                        AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                                        AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2]
        let settings: [String: Any] = [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
                                       AVVideoColorPropertiesKey: colour]
        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        } catch {
            throw failure(error.localizedDescription)
        }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        guard writer.canAdd(input) else { throw failure("The writer refused the video input") }
        let sink: any ClipFrameWriting = SampleClipWriter(writer: writer, input: input)
        if let reason = sink.begin() { throw failure(reason) }
        let base = CIImage(cgImage: image)
        let context = CIContext()
        do throws(LibraryError) {
            for index in 0..<frameCount {
                while !sink.isReady() {
                    if let reason = sink.failure() { throw failure(reason) }
                    do {
                        try await Task.sleep(for: .milliseconds(5))
                    } catch {
                        throw failure("The write was cancelled")
                    }
                }
                let angle = 2 * Double.pi * Double(index) / Double(frameCount)
                guard let frame = Self.frame(of: base, turnedBy: angle, at: index, with: context) else {
                    throw failure("Frame \(index) could not be rendered")
                }
                guard sink.append(frame) else { throw failure(sink.failure() ?? "Frame \(index) was refused") }
            }
            if let reason = await sink.finish() { throw failure(reason) }
        } catch {
            // The writer must not be released while it is still writing; the seeder removes the files.
            sink.cancel()
            throw error
        }
    }

    private static func frame(of base: CIImage, turnedBy angle: Double, at index: Int, with context: CIContext) -> CMSampleBuffer? {
        let filter = CIFilter(name: "CIHueAdjust")
        filter?.setValue(base, forKey: kCIInputImageKey)
        filter?.setValue(angle, forKey: kCIInputAngleKey)
        guard let turned = filter?.outputImage, let space = CGColorSpace(name: CGColorSpace.itur_709) else { return nil }
        var buffer: CVPixelBuffer?
        let attributes: [String: Any] = [kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()]
        guard CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &buffer) == kCVReturnSuccess,
              let buffer else { return nil }
        context.render(turned, to: buffer, bounds: CGRect(x: 0, y: 0, width: width, height: height), colorSpace: space)
        CVBufferSetAttachment(buffer, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(buffer, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(buffer, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2, .shouldPropagate)
        var format: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: buffer, formatDescriptionOut: &format) == noErr,
              let format else { return nil }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: framesPerSecond),
                                        presentationTimeStamp: CMTime(value: CMTimeValue(index), timescale: framesPerSecond),
                                        decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: buffer, formatDescription: format,
                                                       sampleTiming: &timing, sampleBufferOut: &sample) == noErr else { return nil }
        return sample
    }

    @available(iOS, deprecated: 27.0, message: "Uses the writer calls iOS 27 deprecates on purpose; see the type's comment")
    func begin() -> String? {
        writer.add(input)
        guard writer.startWriting() else { return writer.error?.localizedDescription ?? "The writer did not start" }
        writer.startSession(atSourceTime: .zero)
        return nil
    }

    @available(iOS, deprecated: 27.0, message: "Uses the writer calls iOS 27 deprecates on purpose; see the type's comment")
    func isReady() -> Bool {
        input.isReadyForMoreMediaData
    }

    @available(iOS, deprecated: 27.0, message: "Uses the writer calls iOS 27 deprecates on purpose; see the type's comment")
    func append(_ frame: CMSampleBuffer) -> Bool {
        input.append(frame)
    }

    func failure() -> String? {
        writer.status == .failed ? (writer.error?.localizedDescription ?? "The writer failed") : nil
    }

    func cancel() {
        writer.cancelWriting()
    }

    func finish() async -> String? {
        input.markAsFinished()
        await writer.finishWriting()
        return writer.status == .completed ? nil : (writer.error?.localizedDescription ?? "The writer did not finish")
    }
}
