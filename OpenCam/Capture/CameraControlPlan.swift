import Foundation

/// Which system controls the Camera Control offers.
nonisolated enum CameraControlPlan {
    /// None without Camera Control support. RAW photo formats get no zoom, because Bayer RAW needs zoom 1.0
    /// (AVCapturePhotoOutput.h); video mode ignores the photo format.
    static func kinds(supportsControls: Bool, mode: CaptureMode, photoFormat: PhotoFormat) -> [SystemControlKind] {
        guard supportsControls else { return [] }
        if mode == .photo, photoFormat.includesRAW { return [.exposureBias] }
        return [.zoom, .exposureBias]
    }

    /// The Camera Control's exposure bias slider is disabled while exposure is manual, because bias then only affects metering
    /// (AVCaptureDevice.h, `exposureTargetBias`). `AVCaptureControl.isEnabled` needs no session configuration.
    static func enablesExposureBias(for exposure: ManualSettings.Exposure) -> Bool {
        exposure == .automatic
    }
}
