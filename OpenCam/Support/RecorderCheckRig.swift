import AVFoundation

/// A session with only the back wide camera and one video data output: no audio, no preview layer, late frames kept.
/// Used from one task at a time.
nonisolated final class RecorderCheckRig {
    let session = AVCaptureSession()
    let output = AVCaptureVideoDataOutput()
    let device: AVCaptureDevice

    static func backWideCamera() -> AVCaptureDevice? {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .back).devices.first
    }

    /// `preset` is input priority when the format is chosen by hand, or the photo preset to see what that preset offers.
    /// The session only configures wide colour itself on the photo preset, as the app's photo mode does.
    init(device: AVCaptureDevice, preset: AVCaptureSession.Preset) throws {
        self.device = device
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            throw RecorderCheckFailure(message: "The camera input could not be made: \(error.localizedDescription)")
        }
        guard session.canAddInput(input) else { throw RecorderCheckFailure(message: "The session cannot take the camera input") }
        session.addInput(input)
        guard session.canSetSessionPreset(preset) else { throw RecorderCheckFailure(message: "The session cannot use the preset \(preset.rawValue)") }
        session.sessionPreset = preset
        session.automaticallyConfiguresCaptureDeviceForWideColor = preset == .photo
        output.alwaysDiscardsLateVideoFrames = false
        guard session.canAddOutput(output) else { throw RecorderCheckFailure(message: "The session cannot take a video data output") }
        session.addOutput(output)
    }

    /// Full-size buffers, not the preview-sized ones the output may choose by itself (AVCaptureVideoDataOutput.h,
    /// `automaticallyConfiguresOutputBufferDimensions`).
    func requestFullSizeBuffers() {
        output.automaticallyConfiguresOutputBufferDimensions = false
        output.deliversPreviewSizedOutputBuffers = false
    }

    /// Puts the camera on `format` at the target rate, in HLG BT.2020 when the format supports it. The session is not
    /// running yet: changing the colour space of a running session needs a disruptive reconfiguration (AVCaptureDevice.h).
    func apply(format: AVCaptureDevice.Format, target: RecorderCheckTarget) throws {
        guard RecorderCheckFormats.supports(format, framesPerSecond: target.framesPerSecond) else {
            throw RecorderCheckFailure(message: "The format does not offer \(target.framesPerSecond) fps")
        }
        do {
            try device.lockForConfiguration()
        } catch {
            throw RecorderCheckFailure(message: "The camera could not be locked: \(error.localizedDescription)")
        }
        defer { device.unlockForConfiguration() }
        device.activeFormat = format
        let duration = CMTime(value: 1, timescale: CMTimeScale(target.framesPerSecond))
        device.activeVideoMinFrameDuration = duration
        device.activeVideoMaxFrameDuration = duration
        if format.supportedColorSpaces.contains(.HLG_BT2020) {
            device.activeColorSpace = .HLG_BT2020
        }
    }
}
