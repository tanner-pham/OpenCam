import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

/// Sample buffers the camera would deliver, built by hand: 320 x 180 `420v` frames, and 48 kHz mono sound, on one clock.
enum SyntheticFrames {
    static let width = 320
    static let height = 180
    static let framesPerSecond = 30
    /// A non-zero start, like a camera's clock.
    static let origin = CMTime(value: 5_000, timescale: 1)

    enum Failure: Error {
        case pixelBuffer(CVReturn)
        case formatDescription(OSStatus)
        case sampleBuffer(OSStatus)
    }

    static func time(ofFrame index: Int) -> CMTime {
        CMTimeAdd(origin, CMTime(value: CMTimeValue(index), timescale: CMTimeScale(framesPerSecond)))
    }

    static func frame(_ index: Int) throws -> CMSampleBuffer {
        var pixelBuffer: CVPixelBuffer?
        let created = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                                          [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pixelBuffer)
        guard created == kCVReturnSuccess, let pixelBuffer else { throw Failure.pixelBuffer(created) }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        for plane in 0..<CVPixelBufferGetPlaneCount(pixelBuffer) {
            guard let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, plane) else { continue }
            let size = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, plane) * CVPixelBufferGetHeightOfPlane(pixelBuffer, plane)
            memset(base, plane == 0 ? Int32(16 + (index * 5) % 200) : 128, size)
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        CVBufferSetAttachment(pixelBuffer, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(pixelBuffer, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(pixelBuffer, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2, .shouldPropagate)
        var description: CMVideoFormatDescription?
        let described = CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescriptionOut: &description)
        guard described == noErr, let description else { throw Failure.formatDescription(described) }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: CMTimeScale(framesPerSecond)), presentationTimeStamp: time(ofFrame: index), decodeTimeStamp: .invalid)
        var sampleBuffer: CMSampleBuffer?
        let made = CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescription: description,
                                                            sampleTiming: &timing, sampleBufferOut: &sampleBuffer)
        guard made == noErr, let sampleBuffer else { throw Failure.sampleBuffer(made) }
        return sampleBuffer
    }

    /// One frame's worth of 16-bit mono sound (1,600 samples at 48 kHz) starting at frame `index`'s time.
    static func sound(startingAtFrame index: Int) throws -> CMSampleBuffer {
        let samples = 1_600
        var format = AudioStreamBasicDescription(mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM,
                                                 mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked, mBytesPerPacket: 2,
                                                 mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0)
        var description: CMAudioFormatDescription?
        let described = CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &format, layoutSize: 0, layout: nil, magicCookieSize: 0,
                                                       magicCookie: nil, extensions: nil, formatDescriptionOut: &description)
        guard described == noErr, let description else { throw Failure.formatDescription(described) }
        let bytes = samples * 2
        var block: CMBlockBuffer?
        let blockStatus = CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: bytes, blockAllocator: kCFAllocatorDefault,
                                                             customBlockSource: nil, offsetToData: 0, dataLength: bytes, flags: kCMBlockBufferAssureMemoryNowFlag,
                                                             blockBufferOut: &block)
        guard blockStatus == kCMBlockBufferNoErr, let block else { throw Failure.sampleBuffer(blockStatus) }
        CMBlockBufferFillDataBytes(with: 0, blockBuffer: block, offsetIntoDestination: 0, dataLength: bytes)
        var sampleBuffer: CMSampleBuffer?
        let made = CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: description,
                                                                        sampleCount: samples, presentationTimeStamp: time(ofFrame: index),
                                                                        packetDescriptions: nil, sampleBufferOut: &sampleBuffer)
        guard made == noErr, let sampleBuffer else { throw Failure.sampleBuffer(made) }
        return sampleBuffer
    }
}
