import AVFoundation

/// The combined back camera, read from the device at launch.
nonisolated enum CombinedCameraDiscovery {
    /// The first dual wide camera at the back, nil unless it keeps its lens when the zoom crosses a switch-over and has one
    /// switch-over factor between each pair of its cameras. Only properties are read; no session is made.
    static func camera() -> CombinedCamera? {
        let devices = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInDualWideCamera], mediaType: .video, position: .back).devices
        guard let device = devices.first, device.isPrimaryConstituentDeviceSwitchingBehaviorLockedWithDeviceSupported else { return nil }
        let switchOvers = device.virtualDeviceSwitchOverVideoZoomFactors.map(\.doubleValue)
        let constituents = device.constituentDevices
        guard constituents.count == switchOvers.count + 1 else { return nil }
        let baseZooms = [1] + switchOvers
        let formats = device.formats.map { format in
            let dimensions = format.formatDescription.dimensions
            return CombinedFormat(width: Int(dimensions.width), height: Int(dimensions.height),
                                  colourSpaces: format.supportedColorSpaces.map(\.rawValue),
                                  frameRateRanges: format.videoSupportedFrameRateRanges.map { $0.minFrameRate...$0.maxFrameRate },
                                  maxZoomFactor: Double(format.videoMaxZoomFactor))
        }
        return CombinedCamera(deviceUniqueID: device.uniqueID,
                              baseZoomByDeviceID: Dictionary(uniqueKeysWithValues: zip(constituents.map(\.uniqueID), baseZooms)),
                              formats: formats)
    }
}
