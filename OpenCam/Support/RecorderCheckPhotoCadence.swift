import AVFoundation

/// Report section C: ten RAW photos in a row, requested one after the other, then ten requested 100 ms apart. The session is the
/// photo preset with one photo output on the back wide camera; the RAW settings are built the way the app's photo mode builds
/// them (`PhotoCapturer.makeSettings`): the first Bayer format the output offers, a DNG, speed prioritization, the 12 MP size.
nonisolated enum RecorderCheckPhotoCadence {
    private static let photosPerRun = 10
    private static let spacing = Duration.milliseconds(100)
    private static let timeout = Duration.seconds(20)
    private static let twelveMegapixels = 12_000_000

    @concurrent static func run(directory: URL) async -> RecorderCheckRawCadence {
        var cadence = RecorderCheckRawCadence()
        guard let device = RecorderCheckRig.backWideCamera() else {
            cadence.skipReason = RecorderCheck.logError("run", "No back wide camera", context: "section: RAW cadence")
            return cadence
        }
        let session = AVCaptureSession()
        let output = AVCapturePhotoOutput()
        session.beginConfiguration()
        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else { throw RecorderCheckFailure(message: "The session cannot take the camera input") }
            session.addInput(input)
            guard session.canSetSessionPreset(.photo) else { throw RecorderCheckFailure(message: "The session cannot use the photo preset") }
            session.sessionPreset = .photo
            guard session.canAddOutput(output) else { throw RecorderCheckFailure(message: "The session cannot take a photo output") }
            session.addOutput(output)
        } catch {
            session.commitConfiguration()
            cadence.skipReason = RecorderCheck.logError("run", "The session could not be set up", context: "reason: \(RecorderCheck.describe(error))")
            return cadence
        }
        session.commitConfiguration()
        cadence.sessionPreset = session.sessionPreset.rawValue

        // The size is set before the session starts and must be one the active format lists (AVCapturePhotoOutput.h, maxPhotoDimensions).
        let active = device.activeFormat
        let size = active.formatDescription.dimensions
        cadence.activeFormat = "\(size.width)x\(size.height) \(RecorderCheckFourCC.string(active.formatDescription.mediaSubType.rawValue))"
        guard let dimensions = active.supportedMaxPhotoDimensions.min(by: { Self.distance($0) < Self.distance($1) }) else {
            cadence.skipReason = RecorderCheck.logError("run", "The active format lists no photo size", context: "format: \(cadence.activeFormat)")
            return cadence
        }
        output.maxPhotoDimensions = dimensions
        cadence.maxPhotoDimensions = "\(dimensions.width)x\(dimensions.height)"

        session.startRunning()
        defer { session.stopRunning() }
        guard session.isRunning else {
            cadence.skipReason = RecorderCheck.logError("run", "The session did not start", context: "preset: photo")
            return cadence
        }
        // A running session publishes the RAW formats; wait for a Bayer one.
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(5)
        while clock.now < deadline, !output.availableRawPhotoPixelFormatTypes.contains(where: AVCapturePhotoOutput.isBayerRAWPixelFormat) {
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard let raw = output.availableRawPhotoPixelFormatTypes.first(where: AVCapturePhotoOutput.isBayerRAWPixelFormat) else {
            cadence.skipReason = RecorderCheck.logError("run", "The photo output offers no Bayer RAW format", context: "offered: \(output.availableRawPhotoPixelFormatTypes.map(RecorderCheckFourCC.string))")
            return cadence
        }
        cadence.rawPixelFormat = RecorderCheckFourCC.string(raw)
        guard output.availableRawPhotoFileTypes.contains(.dng), output.supportedRawPhotoPixelFormatTypes(for: .dng).contains(raw) else {
            cadence.skipReason = RecorderCheck.logError("run", "DNG is not offered for the RAW format", context: "format: \(cadence.rawPixelFormat)")
            return cadence
        }
        guard AVCapturePhotoOutput.QualityPrioritization.speed.rawValue <= output.maxPhotoQualityPrioritization.rawValue else {
            cadence.skipReason = RecorderCheck.logError("run", "Speed prioritization is above the output maximum", context: "maximum: \(output.maxPhotoQualityPrioritization.rawValue)")
            return cadence
        }
        cadence.photoQualityPrioritization = "speed"

        cadence.oneAfterAnother = await takePhotos(named: "one after another, each requested when the previous one finished",
                                                   raw: raw, output: output, directory: directory, isSpaced: false)
        cadence.every100Milliseconds = await takePhotos(named: "requested 100 ms apart, without waiting",
                                                        raw: raw, output: output, directory: directory, isSpaced: true)
        return cadence
    }

    private static func distance(_ dimensions: CMVideoDimensions) -> Int {
        abs(Int(dimensions.width) * Int(dimensions.height) - twelveMegapixels)
    }

    private static func takePhotos(named name: String, raw: OSType, output: AVCapturePhotoOutput, directory: URL, isSpaced: Bool) async -> RecorderCheckPhotoRun {
        var run = RecorderCheckPhotoRun(name: name)
        let clock = ContinuousClock()
        let start = clock.now
        var delegates: [RecorderCheckPhotoDelegate] = []
        var timers: [Task<Void, Never>] = []
        var shots: [RecorderCheckPhotoShot] = []
        for index in 0..<photosPerRun {
            if isSpaced { try? await clock.sleep(until: start + spacing * index) }
            let delegate = RecorderCheckPhotoDelegate(index: index, runStart: start, fileURL: directory.appending(path: "photo-\(isSpaced ? "spaced" : "serial")-\(index).dng"))
            delegates.append(delegate)
            guard let connection = output.connection(with: .video), connection.isActive else {
                delegate.expire(after: .zero)
                if !isSpaced { shots.append(await delegate.result()) }
                continue
            }
            let settings = AVCapturePhotoSettings(rawPixelFormatType: raw, rawFileType: .dng, processedFormat: nil, processedFileType: nil)
            settings.photoQualityPrioritization = .speed
            settings.maxPhotoDimensions = output.maxPhotoDimensions
            delegate.markRequested()
            output.capturePhoto(with: settings, delegate: delegate)
            let limit = timeout
            timers.append(Task {
                try? await Task.sleep(for: limit)
                guard !Task.isCancelled else { return }
                delegate.expire(after: limit)
            })
            if !isSpaced { shots.append(await delegate.result()) }
        }
        if isSpaced {
            for delegate in delegates { shots.append(await delegate.result()) }
        }
        for timer in timers { timer.cancel() }
        run.totalSeconds = (clock.now - start).recorderCheckMilliseconds / 1000
        run.shots = shots
        run.photosCompleted = shots.filter { $0.error == nil }.count
        run.photosPerSecond = run.totalSeconds > 0 ? Double(run.photosCompleted) / run.totalSeconds : nil
        return run
    }
}
