import AVFoundation

/// The lenses the lens menu offers, read from the device at launch.
nonisolated enum LensDiscovery {
    static func lenses() -> [Lens] {
        // Wide and ultra wide come from the back only, so a front wide camera never shows as a second "1x".
        let back = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInUltraWideCamera, .builtInWideAngleCamera], mediaType: .video, position: .back).devices
        // The SDK does not say which position the Duo's outer and inner ultra wides report, so any position is accepted.
        let front = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInOuterUltraWideCamera, .builtInInnerUltraWideCamera], mediaType: .video, position: .unspecified).devices

        var seen = Set<String>()
        var lenses: [Lens] = []
        for device in back + front where seen.insert(device.uniqueID).inserted {
            guard let kind = kind(of: device.deviceType) else { continue }
            lenses.append(lens(device: device, kind: kind, zoomFactor: 1))
            if kind == .wide {
                lenses.append(lens(device: device, kind: kind, zoomFactor: 2))
            }
        }
        let order: [LensKind] = [.ultraWide, .wide, .outerUltraWide, .innerUltraWide]
        return lenses.sorted { lhs, rhs in
            let left = order.firstIndex(of: lhs.kind) ?? order.count, right = order.firstIndex(of: rhs.kind) ?? order.count
            return left == right ? lhs.zoomFactor < rhs.zoomFactor : left < right
        }
    }

    private static func lens(device: AVCaptureDevice, kind: LensKind, zoomFactor: Double) -> Lens {
        Lens(id: zoomFactor == 1 ? device.uniqueID : "\(device.uniqueID)@\(Int(zoomFactor))",
             kind: kind,
             deviceUniqueID: device.uniqueID,
             zoomFactor: zoomFactor,
             label: LensLabel.text(kind: kind, zoomFactor: zoomFactor, localizedName: device.localizedName))
    }

    private static func kind(of type: AVCaptureDevice.DeviceType) -> LensKind? {
        switch type {
        case .builtInUltraWideCamera: .ultraWide
        case .builtInWideAngleCamera: .wide
        case .builtInOuterUltraWideCamera: .outerUltraWide
        case .builtInInnerUltraWideCamera: .innerUltraWide
        default: nil
        }
    }
}
