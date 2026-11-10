import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

enum RawMethod: Sendable {
    case single(inFlight: Int)
    case bracket
    case video(deviceID: String, formatIndex: Int)

    var label: String {
        switch self {
        case .single(let n): "single Bayer RAW captures, \(n) in flight"
        case .bracket: "Bayer RAW brackets at max bracket count"
        case .video(_, let index): "video data output Bayer stream, format #\(index)"
        }
    }
}

/// Owns one session on one camera and counts RAW frames without keeping them.
final class RawTester: NSObject, AVCapturePhotoCaptureDelegate, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let device: AVCaptureDevice
    private let queue = DispatchQueue(label: "local.duocam.probe.raw")
    private let session = AVCaptureSession()
    private let photo = AVCapturePhotoOutput()
    private let video = AVCaptureVideoDataOutput()
    private var rawFormat: OSType = 0
    private(set) var formatDescription = ""

    private let lock = NSLock()
    private var stamps: [TimeInterval] = []
    private var inFlight = 0
    private var errorCounts: [String: Int] = [:]
    private var width: Int32?
    private var height: Int32?
    private var bitDepth: Int?

    init(device: AVCaptureDevice) { self.device = device }

    private func onQueue<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { continuation.resume(with: Result { try work() }) }
        }
    }

    private func pixels(_ d: CMVideoDimensions) -> Int { Int(d.width) * Int(d.height) }

    // MARK: Configuration

    func configurePhoto() async throws {
        try await onQueue { try self.configurePhotoSync() }
        try? await Task.sleep(for: .seconds(1))
    }

    private func configurePhotoSync() throws {
        let input = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        session.sessionPreset = .inputPriority
        guard session.canAddInput(input), session.canAddOutput(photo) else {
            session.commitConfiguration()
            throw ProbeError(site: "RawTest:configurePhoto", detail: "cannot add input or photo output for \(device.localizedName)")
        }
        session.addInput(input)
        session.addOutput(photo)
        session.commitConfiguration()

        let candidates = device.formats
            .compactMap { format in format.supportedMaxPhotoDimensions.max(by: { pixels($0) < pixels($1) }).map { (format, $0) } }
            .sorted { pixels($0.1) > pixels($1.1) }
        for (format, largest) in candidates.prefix(10) {
            guard Inventory.setActive(format, on: device) else { continue }
            photo.maxPhotoDimensions = largest
            if let bayer = photo.availableRawPhotoPixelFormatTypes.first(where: AVCapturePhotoOutput.isBayerRAWPixelFormat) {
                rawFormat = bayer
                let dims = format.formatDescription.dimensions
                formatDescription = "\(dims.width)x\(dims.height) \(fourCC(format.formatDescription.mediaSubType.rawValue)), max photo \(largest.width)x\(largest.height), RAW \(fourCC(bayer))"
                session.startRunning()
                return
            }
        }
        throw ProbeError(site: "RawTest:configurePhoto", detail: "no format of \(device.localizedName) offered a Bayer RAW photo pixel format")
    }

    func configureVideo(formatIndex: Int) async throws {
        try await onQueue { try self.configureVideoSync(formatIndex: formatIndex) }
        try? await Task.sleep(for: .seconds(1))
    }

    private func configureVideoSync(formatIndex: Int) throws {
        guard device.formats.indices.contains(formatIndex) else {
            throw ProbeError(site: "RawTest:configureVideo", detail: "format index \(formatIndex) out of range")
        }
        let format = device.formats[formatIndex]
        let input = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        session.sessionPreset = .inputPriority
        guard session.canAddInput(input), session.canAddOutput(video) else {
            session.commitConfiguration()
            throw ProbeError(site: "RawTest:configureVideo", detail: "cannot add input or video data output")
        }
        session.addInput(input)
        session.addOutput(video)
        session.commitConfiguration()
        guard Inventory.setActive(format, on: device) else {
            throw ProbeError(site: "RawTest:configureVideo", detail: "cannot select format \(formatIndex)")
        }
        guard let bayer = video.availableVideoPixelFormatTypes.first(where: Inventory.isBayerVideo) else {
            throw ProbeError(site: "RawTest:configureVideo", detail: "format \(formatIndex) offers no Bayer pixel format on the video data output")
        }
        video.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: bayer]
        video.alwaysDiscardsLateVideoFrames = true
        video.setSampleBufferDelegate(self, queue: queue)
        if let fastest = format.videoSupportedFrameRateRanges.max(by: { $0.maxFrameRate < $1.maxFrameRate }) {
            try device.lockForConfiguration()
            device.activeVideoMinFrameDuration = fastest.minFrameDuration
            device.activeVideoMaxFrameDuration = fastest.minFrameDuration
            device.unlockForConfiguration()
        }
        let dims = format.formatDescription.dimensions
        formatDescription = "\(dims.width)x\(dims.height) \(fourCC(format.formatDescription.mediaSubType.rawValue)), pixel format \(fourCC(bayer))"
        session.startRunning()
    }

    func stop() async {
        _ = try? await onQueue {
            self.video.setSampleBufferDelegate(nil, queue: nil)
            self.session.stopRunning()
            self.session.beginConfiguration()
            self.session.inputs.forEach { self.session.removeInput($0) }
            self.session.outputs.forEach { self.session.removeOutput($0) }
            self.session.commitConfiguration()
        }
    }

    // MARK: Runs

    private func reset() {
        lock.withLock {
            stamps = []; inFlight = 0; errorCounts = [:]; width = nil; height = nil; bitDepth = nil
        }
    }

    private func noteError(_ message: String) {
        lock.withLock { errorCounts[message, default: 0] += 1 }
    }

    private func requestSingle(limit: Int) -> Bool {
        let issue = lock.withLock { () -> Bool in
            guard inFlight < limit else { return false }
            inFlight += 1
            return true
        }
        guard issue else { return false }
        let settings = AVCapturePhotoSettings(rawPixelFormatType: rawFormat)
        settings.photoQualityPrioritization = .speed
        settings.maxPhotoDimensions = photo.maxPhotoDimensions
        photo.capturePhoto(with: settings, delegate: self)
        return true
    }

    private func requestBracket(count: Int) -> Bool {
        let issue = lock.withLock { () -> Bool in
            guard inFlight < 1 else { return false }
            inFlight += 1
            return true
        }
        guard issue else { return false }
        let bracketed = (0..<count).map { _ in
            AVCaptureAutoExposureBracketedStillImageSettings.autoExposureSettings(exposureTargetBias: AVCaptureDevice.currentExposureTargetBias)
        }
        let settings = AVCapturePhotoBracketSettings(rawPixelFormatType: rawFormat, processedFormat: nil, bracketedSettings: bracketed)
        settings.photoQualityPrioritization = .speed
        settings.maxPhotoDimensions = photo.maxPhotoDimensions
        photo.capturePhoto(with: settings, delegate: self)
        return true
    }

    func run(_ method: RawMethod, seconds: Double) async -> RawRun {
        var run = RawRun(method: method.label, seconds: seconds)
        run.thermalBefore = Inventory.thermalName(ProcessInfo.processInfo.thermalState)
        reset()
        var bracketCount = 0
        if case .bracket = method {
            bracketCount = Int(photo.maxBracketedCapturePhotoCount)
            if bracketCount == 0 {
                run.errors.append("[RawTest:run] maxBracketedCapturePhotoCount is 0 at this format, brackets unsupported")
                run.thermalAfter = run.thermalBefore
                return run
            }
            run.method += " (\(bracketCount))"
        }
        let start = ProcessInfo.processInfo.systemUptime
        let end = start + seconds
        while ProcessInfo.processInfo.systemUptime < end {
            let issued: Bool
            switch method {
            case .single(let limit): issued = requestSingle(limit: limit)
            case .bracket: issued = requestBracket(count: bracketCount)
            case .video: issued = false
            }
            if !issued { try? await Task.sleep(for: .milliseconds(1)) }
        }
        // Let outstanding requests finish so they do not leak into the next run.
        let drainDeadline = ProcessInfo.processInfo.systemUptime + 5
        while lock.withLock({ inFlight }) > 0 && ProcessInfo.processInfo.systemUptime < drainDeadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        run.thermalAfter = Inventory.thermalName(ProcessInfo.processInfo.thermalState)

        let snapshot = lock.withLock { (stamps.filter { $0 >= start && $0 <= end }, errorCounts, width, height, bitDepth, inFlight) }
        let (inWindow, errors, w, h, depth, stuck) = snapshot
        run.framesDelivered = inWindow.count
        run.fps = Double(inWindow.count) / seconds
        let gaps = zip(inWindow.dropFirst(), inWindow).map { ($0 - $1) * 1000 }
        if !gaps.isEmpty {
            run.avgIntervalMs = gaps.reduce(0, +) / Double(gaps.count)
            run.worstIntervalMs = gaps.max()
        }
        run.rawWidth = w
        run.rawHeight = h
        run.bitDepth = depth
        run.errors = errors.map { "\($0.key) x\($0.value)" }.sorted()
        if stuck > 0 { run.errors.append("[RawTest:run] \(stuck) requests still in flight after 5 s drain") }
        return run
    }

    // MARK: Delegates

    private func noteFrame(_ buffer: CVPixelBuffer?) {
        let now = ProcessInfo.processInfo.systemUptime
        lock.withLock {
            stamps.append(now)
            if let buffer, width == nil {
                width = Int32(CVPixelBufferGetWidth(buffer))
                height = Int32(CVPixelBufferGetHeight(buffer))
                let type = CVPixelBufferGetPixelFormatType(buffer)
                bitDepth = type == kCVPixelFormatType_16VersatileBayer ? 16 : type == kCVPixelFormatType_96VersatileBayerPacked12 ? 12 : 14
            }
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error {
            noteError(errorMessage(error, site: "RawTest:didFinishProcessingPhoto"))
        } else if photo.isRawPhoto {
            noteFrame(photo.pixelBuffer)
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        if let error { noteError(errorMessage(error, site: "RawTest:didFinishCapture")) }
        lock.withLock { inFlight -= 1 }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        noteFrame(CMSampleBufferGetImageBuffer(sampleBuffer))
    }
}

enum RawTest {
    static func execute(_ method: RawMethod, seconds: Double, log: Log) async -> (run: RawRun, format: String) {
        var failed = RawRun(method: method.label, seconds: seconds)
        let device: AVCaptureDevice?
        if case .video(let id, _) = method {
            device = AVCaptureDevice(uniqueID: id)
        } else {
            device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        }
        guard let device else {
            failed.errors.append("[RawTest:execute] camera not found")
            return (failed, "")
        }
        let tester = RawTester(device: device)
        do {
            if case .video(_, let index) = method {
                try await tester.configureVideo(formatIndex: index)
            } else {
                try await tester.configurePhoto()
            }
        } catch {
            await tester.stop()
            failed.errors.append(errorMessage(error, site: "RawTest:execute"))
            return (failed, "")
        }
        log("Running \(method.label), \(Int(seconds)) s")
        let run = await tester.run(method, seconds: seconds)
        let format = tester.formatDescription
        await tester.stop()
        log(String(format: "  %d frames, %.2f fps, worst gap %.0f ms", run.framesDelivered, run.fps, run.worstIntervalMs ?? 0))
        return (run, format)
    }

    static func run(cameras: [CameraInfo], log: Log, checkpoint: @Sendable (RawTestInfo) -> Void) async -> RawTestInfo {
        var info = RawTestInfo()
        guard let main = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            info.errors.append("[RawTest:run] no main back wide camera, test skipped")
            return info
        }
        info.cameraName = main.localizedName
        var methods: [RawMethod] = [.single(inFlight: 1), .single(inFlight: 2), .single(inFlight: 4), .bracket]
        let hit = cameras.first { $0.uniqueID == main.uniqueID && !$0.outputs.bayerVideoFormats.isEmpty }
            ?? cameras.first { !$0.outputs.bayerVideoFormats.isEmpty }
        if let hit, let first = hit.outputs.bayerVideoFormats.first {
            methods.append(.video(deviceID: hit.uniqueID, formatIndex: first.formatIndex))
        } else {
            log("No Bayer pixel format on any video data output, skipping stream test")
        }
        var best: (method: RawMethod, run: RawRun)?
        for method in methods {
            let result = await execute(method, seconds: 10, log: log)
            if info.format == nil, !result.format.isEmpty, case .single = method { info.format = result.format }
            info.runs.append(result.run)
            if result.run.fps > (best?.run.fps ?? 0) { best = (method, result.run) }
            checkpoint(info)
        }
        if let best, best.run.fps > 0 {
            log("Fastest: \(best.run.method), now 60 s sustained run")
            let sustained = await execute(best.method, seconds: 60, log: log)
            info.sustainedRun = sustained.run
            if info.format == nil { info.format = sustained.format }
        } else {
            info.errors.append("[RawTest:run] no method delivered a frame, sustained run skipped")
        }
        return info
    }
}
