import AVFoundation
import ImageIO
import Synchronization

/// One frame as the lens check keeps it. The aperture tells the two back lenses apart (f/2.2 ultra wide, f/1.6 wide).
nonisolated struct LensCheckFrame: Sendable {
    /// Seconds on the session's synchronisation clock.
    var captured: Double
    /// Seconds on the host clock.
    var arrived: Double
    var aperture: Double?
    var exposureSeconds: Double?
    var iso: Double?
    var digitalZoom: Double?
}

/// What happened since the last `reset()`.
nonisolated struct LensCheckWindow: Sendable {
    var frames: [LensCheckFrame] = []
    var dropped = 0
    var dropReasons: [String] = []
    /// Host-clock seconds and the lens the combined camera reported as active.
    var lensChanges: [(at: Double, lens: String)] = []
    /// Host-clock seconds at which a zoom ramp reported it had ended.
    var rampEnds: [Double] = []
}

/// The lens check's frame delegate: keeps a few numbers per frame and the times the camera reported a lens change.
nonisolated final class LensCheckTap: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, Sendable {
    private struct State {
        var window = LensCheckWindow()
        var total = 0
        var firstFrame: [String: String] = [:]
        var last: LensCheckFrame?
    }

    private let state = Mutex(State())
    let queue = DispatchSerialQueue(label: "opencam.lenscheck.frames", qos: .userInitiated)

    static func hostNow() -> Double { CMClockGetTime(CMClockGetHostTimeClock()).seconds }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let arrived = Self.hostNow()
        let exif = CMGetAttachment(sampleBuffer, key: kCGImagePropertyExifDictionary, attachmentModeOut: nil) as? [String: Any]
        let frame = LensCheckFrame(
            captured: CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds, arrived: arrived,
            aperture: Self.number(exif?[kCGImagePropertyExifFNumber as String]),
            exposureSeconds: Self.number(exif?[kCGImagePropertyExifExposureTime as String]),
            iso: Self.number((exif?[kCGImagePropertyExifISOSpeedRatings as String] as? [Any])?.first),
            digitalZoom: Self.number(exif?[kCGImagePropertyExifDigitalZoomRatio as String]))
        let isFirst = state.withLock { state in
            state.window.frames.append(frame)
            state.last = frame
            state.total += 1
            return state.total == 1
        }
        guard isFirst else { return }
        let facts = Self.describe(sampleBuffer, exif: exif)
        state.withLock { $0.firstFrame = facts }
    }

    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let reason = CMGetAttachment(sampleBuffer, key: kCMSampleBufferAttachmentKey_DroppedFrameReason, attachmentModeOut: nil) as? String ?? "unknown"
        state.withLock { state in
            state.window.dropped += 1
            if !state.window.dropReasons.contains(reason) { state.window.dropReasons.append(reason) }
        }
    }

    func noteLens(_ lens: String) {
        let now = Self.hostNow()
        state.withLock { $0.window.lensChanges.append((now, lens)) }
    }

    func noteRampEnded() {
        let now = Self.hostNow()
        state.withLock { $0.window.rampEnds.append(now) }
    }

    func reset() {
        state.withLock { $0.window = LensCheckWindow() }
    }

    func take() -> LensCheckWindow {
        state.withLock { $0.window }
    }

    var total: Int { state.withLock { $0.total } }
    var last: LensCheckFrame? { state.withLock { $0.last } }
    /// The first frame's size, pixel format, colour tags and which attachments it carries.
    var firstFrame: [String: String] { state.withLock { $0.firstFrame } }

    private static func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    private static func describe(_ sampleBuffer: CMSampleBuffer, exif: [String: Any]?) -> [String: String] {
        var facts: [String: String] = [:]
        let attachments = CMCopyDictionaryOfAttachments(allocator: kCFAllocatorDefault, target: sampleBuffer, attachmentMode: kCMAttachmentMode_ShouldPropagate) as? [String: Any]
        facts["frame attachments"] = (attachments?.keys.sorted() ?? []).joined(separator: ", ")
        facts["frame exif keys"] = (exif?.keys.sorted() ?? []).joined(separator: ", ")
        for key in ["LensModel", "FocalLength", "FocalLenIn35mmFilm", "FNumber", "DigitalZoomRatio"] {
            if let value = exif?[key] { facts["frame exif \(key)"] = String(describing: value) }
        }
        guard let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return facts }
        facts["frame size"] = "\(CVPixelBufferGetWidth(pixels))x\(CVPixelBufferGetHeight(pixels))"
        facts["frame pixel format"] = fourCC(CVPixelBufferGetPixelFormatType(pixels))
        for (name, key) in [("transfer", kCVImageBufferTransferFunctionKey), ("primaries", kCVImageBufferColorPrimariesKey), ("matrix", kCVImageBufferYCbCrMatrixKey)] {
            if let value = CVBufferCopyAttachment(pixels, key, nil) { facts["frame \(name)"] = String(describing: value) }
        }
        return facts
    }

    /// Four-character codes ('x420') as text; a code with unprintable bytes prints as its number.
    static func fourCC(_ code: UInt32) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: code >> $0) }
        guard bytes.allSatisfy({ $0 >= 32 && $0 < 127 }) else { return String(code) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
