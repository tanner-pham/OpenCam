import AVFoundation

/// Owns the photo output and makes each request. Used only on the `CameraSession` actor.
/// Every request is checked against what the output reports before it is made, because an invalid request
/// raises an Objective-C exception Swift cannot catch (AVCapturePhotoOutput.h, `capturePhotoWithSettings:delegate:`).
nonisolated final class PhotoCapturer {
    let output = AVCapturePhotoOutput()

    /// `deviceZoom` is the source camera's `videoZoomFactor`; `isExposureManual` is whether the camera's exposure mode is custom.
    /// Throws when the request cannot be made; once made, the result carries the files written and any error.
    func capture(format: PhotoFormat, deviceZoom: Double, isExposureManual: Bool, dngURL: URL, heicURL: URL) async throws(PhotoCaptureError) -> PhotoCaptureResult {
        let settings = try makeSettings(format: format, deviceZoom: deviceZoom, isExposureManual: isExposureManual)
        let delegate = PhotoCaptureDelegate(dngURL: dngURL, heicURL: heicURL)
        let result = await withCheckedContinuation { continuation in
            delegate.deliver(to: continuation)
            output.capturePhoto(with: settings, delegate: delegate)
        }
        // Held until the capture finishes, whether or not the output keeps its own reference.
        withExtendedLifetime(delegate) {}
        return result
    }

    private func makeSettings(format: PhotoFormat, deviceZoom: Double, isExposureManual: Bool) throws(PhotoCaptureError) -> AVCapturePhotoSettings {
        guard let connection = output.connection(with: .video), connection.isActive else {
            throw .captureFailed(reason: "photo output has no active camera connection")
        }
        // Bayer RAW needs both the device zoom and the connection's scale-and-crop at 1.0; both are at least 1.0.
        let zoom = deviceZoom * Double(connection.videoScaleAndCropFactor)
        let plan = try PhotoSettingsPlan.make(format: format, availableRawFormats: output.availableRawPhotoPixelFormatTypes,
                                              isBayer: AVCapturePhotoOutput.isBayerRAWPixelFormat, zoomFactor: zoom,
                                              isExposureManual: isExposureManual)
        if let raw = plan.rawPixelFormat {
            guard output.availableRawPhotoFileTypes.contains(.dng), output.supportedRawPhotoPixelFormatTypes(for: .dng).contains(raw) else {
                throw .captureFailed(reason: "DNG not offered for RAW format \(raw)")
            }
        }
        if plan.wantsProcessedHEIF {
            guard output.availablePhotoCodecTypes.contains(.hevc), output.availablePhotoFileTypes.contains(.heic),
                  output.supportedPhotoCodecTypes(for: .heic).contains(.hevc) else {
                throw .captureFailed(reason: "HEVC in HEIC not offered")
            }
        }
        let prioritization: AVCapturePhotoOutput.QualityPrioritization = plan.prioritizesSpeed ? .speed : .balanced
        guard prioritization.rawValue <= output.maxPhotoQualityPrioritization.rawValue else {
            throw .captureFailed(reason: "quality prioritization \(prioritization.rawValue) above the output maximum \(output.maxPhotoQualityPrioritization.rawValue)")
        }
        // A RAW pixel format of 0 asks for no RAW photo (AVCapturePhotoOutput.h, photoSettingsWithRawPixelFormatType:rawFileType:...).
        let hevc: [String: Any] = [AVVideoCodecKey: AVVideoCodecType.hevc]
        let settings = AVCapturePhotoSettings(
            rawPixelFormatType: plan.rawPixelFormat ?? 0,
            rawFileType: plan.rawPixelFormat == nil ? nil : .dng,
            processedFormat: plan.wantsProcessedHEIF ? hevc : nil,
            processedFileType: plan.wantsProcessedHEIF ? .heic : nil
        )
        settings.photoQualityPrioritization = prioritization
        settings.maxPhotoDimensions = output.maxPhotoDimensions
        return settings
    }
}
