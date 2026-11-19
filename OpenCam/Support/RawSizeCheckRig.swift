import AVFoundation

/// One capture session that holds one back camera and one photo output, nothing else. Every value is checked against what the
/// format or the output reports before it is set, because AVFoundation raises Objective-C exceptions for unsupported values and
/// Swift cannot catch them.
nonisolated final class RawSizeCheckRig {
    let device: AVCaptureDevice
    let session = AVCaptureSession()
    let output = AVCapturePhotoOutput()

    /// With a format, the session uses the input's format (`.inputPriority`) and the format is made active before the session
    /// starts; without one, the photo preset chooses the format.
    init(device: AVCaptureDevice, format: AVCaptureDevice.Format?) throws(RawSizeCheckFailure) {
        self.device = device
        let context = "camera: \(device.localizedName)"
        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            throw RawSizeCheckFailure("Rig.init", "The camera input could not be made", context: "\(context), reason: \(error.localizedDescription)", outcome: .refused)
        }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if format == nil {
            guard session.canSetSessionPreset(.photo) else {
                throw RawSizeCheckFailure("Rig.init", "The session cannot take the photo preset", context: context, outcome: .refused)
            }
            session.sessionPreset = .photo
        } else {
            session.sessionPreset = .inputPriority
        }
        guard session.canAddInput(input), session.canAddOutput(output) else {
            throw RawSizeCheckFailure("Rig.init", "The session cannot take the camera with a photo output", context: context, outcome: .refused)
        }
        session.addInput(input)
        session.addOutput(output)
        if let format {
            try Self.select(format, on: device)
        }
    }

    /// Starts the session and waits for it to publish what its output supports.
    nonisolated(nonsending) func start() async throws(RawSizeCheckFailure) {
        session.startRunning()
        try? await Task.sleep(for: .milliseconds(1_200))
        guard session.isRunning else {
            throw RawSizeCheckFailure("Rig.start", "The session did not start", context: "camera: \(device.localizedName)", outcome: .refused)
        }
    }

    func stop() {
        session.stopRunning()
    }

    var presetName: String { session.sessionPreset.rawValue }

    /// Sets the output's largest photo size, which must be one the active format lists.
    nonisolated(nonsending) func setMaxPhotoDimensions(_ size: RawSizeCheckSize) async throws(RawSizeCheckFailure) {
        guard Self.lists(device.activeFormat.supportedMaxPhotoDimensions, size) else {
            throw RawSizeCheckFailure("Rig.setMaxPhotoDimensions", "The active format does not list this size",
                                      context: "size: \(size.label), listed: \(device.activeFormat.supportedMaxPhotoDimensions.map { RawSizeCheckSize($0).label })")
        }
        session.beginConfiguration()
        output.maxPhotoDimensions = size.dimensions
        session.commitConfiguration()
        try? await Task.sleep(for: .milliseconds(300))
    }

    /// Turns Apple ProRAW on or off, only where the output says it is supported.
    nonisolated(nonsending) func setProRAW(_ isEnabled: Bool) async throws(RawSizeCheckFailure) {
        guard output.isAppleProRAWSupported else {
            throw RawSizeCheckFailure("Rig.setProRAW", "Apple ProRAW is not supported by the output", context: "camera: \(device.localizedName)", outcome: .refused)
        }
        session.beginConfiguration()
        output.isAppleProRAWEnabled = isEnabled
        session.commitConfiguration()
        try? await Task.sleep(for: .milliseconds(300))
    }

    /// Makes another format active on the running session. False when that cannot be done safely, and the caller then makes a
    /// new rig: the output's photo size has to be one the format lists, so when the current size is not listed by the new
    /// format the size is first moved, while the old format is still active, to the smallest size both formats list.
    nonisolated(nonsending) func switchFormat(to format: AVCaptureDevice.Format) async -> Bool {
        guard device.formats.contains(format) else { return false }
        let current = output.maxPhotoDimensions
        let next = format.supportedMaxPhotoDimensions
        if !RawSizeCheckSize(current).isEmpty, !Self.lists(next, RawSizeCheckSize(current)) {
            let shared = device.activeFormat.supportedMaxPhotoDimensions.filter { Self.lists(next, RawSizeCheckSize($0)) }
            guard let bridge = shared.min(by: { $0.width * $0.height < $1.width * $1.height }) else { return false }
            session.beginConfiguration()
            output.maxPhotoDimensions = bridge
            session.commitConfiguration()
        }
        session.beginConfiguration()
        session.sessionPreset = .inputPriority
        let isSelected: Bool
        do throws(RawSizeCheckFailure) {
            try Self.select(format, on: device)
            isSelected = true
        } catch {
            isSelected = false
        }
        session.commitConfiguration()
        try? await Task.sleep(for: .milliseconds(500))
        return isSelected
    }

    private static func select(_ format: AVCaptureDevice.Format, on device: AVCaptureDevice) throws(RawSizeCheckFailure) {
        guard device.formats.contains(format) else {
            throw RawSizeCheckFailure("Rig.select", "The camera does not have this format", context: "camera: \(device.localizedName)")
        }
        do {
            try device.lockForConfiguration()
        } catch {
            throw RawSizeCheckFailure("Rig.select", "The camera could not be locked", context: "camera: \(device.localizedName), reason: \(error.localizedDescription)", outcome: .refused)
        }
        device.activeFormat = format
        device.unlockForConfiguration()
    }

    private static func lists(_ dimensions: [CMVideoDimensions], _ size: RawSizeCheckSize) -> Bool {
        dimensions.contains { Int($0.width) == size.width && Int($0.height) == size.height }
    }

    /// What the output offers now.
    func availability() -> RawSizeCheckAvailability {
        let formats = output.availableRawPhotoPixelFormatTypes.map { code in
            let kind = AVCapturePhotoOutput.isBayerRAWPixelFormat(code) ? "bayer" : AVCapturePhotoOutput.isAppleProRAWPixelFormat(code) ? "proRAW" : "other"
            return RawSizeCheckRawFormat(code: RawSizeCheckFourCC.string(code), kind: kind)
        }
        return RawSizeCheckAvailability(maxPhotoDimensionsSet: RawSizeCheckSize(output.maxPhotoDimensions), rawPixelFormats: formats,
                                        rawFileTypes: output.availableRawPhotoFileTypes.map(\.rawValue),
                                        isAppleProRAWSupported: output.isAppleProRAWSupported, isAppleProRAWEnabled: output.isAppleProRAWEnabled,
                                        maxPhotoQualityPrioritization: output.maxPhotoQualityPrioritization.rawValue)
    }
}
