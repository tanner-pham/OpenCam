import AVFoundation

/// A back camera the check tries.
nonisolated struct RawSizeCheckCamera {
    let device: AVCaptureDevice
    /// "wide", "ultra wide" or "dual wide".
    let name: String

    /// The single-lens cameras, then the combined one, as the phone has them; a missing camera is left out.
    static func discover() -> [RawSizeCheckCamera] {
        let types: [(AVCaptureDevice.DeviceType, String)] = [(.builtInWideAngleCamera, "wide"), (.builtInUltraWideCamera, "ultra wide"),
                                                              (.builtInDualWideCamera, "dual wide")]
        let found = AVCaptureDevice.DiscoverySession(deviceTypes: types.map(\.0), mediaType: .video, position: .back).devices
        return types.compactMap { type, name in
            found.first { $0.deviceType == type }.map { RawSizeCheckCamera(device: $0, name: name) }
        }
    }
}
