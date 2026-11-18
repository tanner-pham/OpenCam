import AVFoundation

nonisolated extension RawSizeCheckRig {
    /// Takes one photo of `kind` with the request's largest photo size set to `size`. Throws, without making a request, when
    /// something the request needs is not offered. A capture that was made always returns, also after an error or a timeout.
    nonisolated(nonsending) func capture(kind: RawSizeCheckKind, size: RawSizeCheckSize, timeout: Duration) async throws(RawSizeCheckFailure) -> RawSizeCheckCapture {
        let (settings, rawFormat) = try makeSettings(kind: kind, size: size)
        let delegate = RawSizeCheckDelegate()
        let clock = ContinuousClock()
        let started = clock.now
        let timer = Task {
            do {
                try await Task.sleep(for: timeout)
            } catch {
                return
            }
            delegate.expire(after: timeout)
        }
        let outcome = await withCheckedContinuation { continuation in
            delegate.deliver(to: continuation)
            output.capturePhoto(with: settings, delegate: delegate)
        }
        timer.cancel()
        withExtendedLifetime(delegate) {}
        let elapsed = clock.now - started
        let milliseconds = Int(elapsed.components.seconds) * 1_000 + Int(elapsed.components.attoseconds / 1_000_000_000_000_000)
        return RawSizeCheckCapture(kind: kind, rawPixelFormat: RawSizeCheckFourCC.string(rawFormat), requestedMaxPhotoDimensions: size,
                                   resolvedRawPhotoDimensions: outcome.rawDimensions, resolvedPhotoDimensions: outcome.photoDimensions,
                                   photos: outcome.photos, milliseconds: milliseconds, isTimedOut: outcome.isTimedOut, error: outcome.error)
    }

    private func makeSettings(kind: RawSizeCheckKind, size: RawSizeCheckSize) throws(RawSizeCheckFailure) -> (AVCapturePhotoSettings, OSType) {
        let context = "camera: \(device.localizedName), kind: \(kind.rawValue), size: \(size.label)"
        guard let connection = output.connection(with: .video), connection.isActive else {
            throw RawSizeCheckFailure("Rig.makeSettings", "The photo output has no active camera connection", context: context)
        }
        // Bayer RAW needs both the device zoom and the connection's scale-and-crop at exactly 1.0 (PhotoCapturer does the same).
        guard device.videoZoomFactor == 1, connection.videoScaleAndCropFactor == 1 else {
            throw RawSizeCheckFailure("Rig.makeSettings", "The zoom is not 1.0", context: "\(context), zoom: \(device.videoZoomFactor), scaleAndCrop: \(connection.videoScaleAndCropFactor)")
        }
        let set = RawSizeCheckSize(output.maxPhotoDimensions)
        guard set == size, device.activeFormat.supportedMaxPhotoDimensions.contains(where: { RawSizeCheckSize($0) == size }) else {
            throw RawSizeCheckFailure("Rig.makeSettings", "The size is not the output's size or not listed by the active format", context: "\(context), output: \(set.label)")
        }
        let available = output.availableRawPhotoPixelFormatTypes
        let rawFormat: OSType?
        switch kind {
        case .bayerRAW, .bayerRAWWithHEIF:
            rawFormat = available.first(where: AVCapturePhotoOutput.isBayerRAWPixelFormat)
        case .proRAW:
            rawFormat = output.isAppleProRAWEnabled ? available.first(where: AVCapturePhotoOutput.isAppleProRAWPixelFormat) : nil
        }
        guard let rawFormat, available.contains(rawFormat) else {
            throw RawSizeCheckFailure("Rig.makeSettings", "No matching RAW pixel format is offered", context: "\(context), available: \(available.map(RawSizeCheckFourCC.string))")
        }
        guard output.availableRawPhotoFileTypes.contains(.dng), output.supportedRawPhotoPixelFormatTypes(for: .dng).contains(rawFormat) else {
            throw RawSizeCheckFailure("Rig.makeSettings", "DNG is not offered for the RAW pixel format", context: "\(context), format: \(RawSizeCheckFourCC.string(rawFormat))")
        }
        let wantsHEIF = kind == .bayerRAWWithHEIF
        if wantsHEIF {
            guard output.availablePhotoCodecTypes.contains(.hevc), output.availablePhotoFileTypes.contains(.heic),
                  output.supportedPhotoCodecTypes(for: .heic).contains(.hevc) else {
                throw RawSizeCheckFailure("Rig.makeSettings", "HEVC in HEIC is not offered", context: context)
            }
        }
        let prioritization = AVCapturePhotoOutput.QualityPrioritization.speed
        guard prioritization.rawValue <= output.maxPhotoQualityPrioritization.rawValue else {
            throw RawSizeCheckFailure("Rig.makeSettings", "The quality prioritization is above the output maximum",
                                      context: "\(context), maximum: \(output.maxPhotoQualityPrioritization.rawValue)")
        }
        let hevc: [String: Any] = [AVVideoCodecKey: AVVideoCodecType.hevc]
        let settings = AVCapturePhotoSettings(rawPixelFormatType: rawFormat, rawFileType: .dng,
                                              processedFormat: wantsHEIF ? hevc : nil, processedFileType: wantsHEIF ? .heic : nil)
        settings.photoQualityPrioritization = prioritization
        settings.maxPhotoDimensions = size.dimensions
        return (settings, rawFormat)
    }
}
