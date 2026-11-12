import Foundation

/// What one photo request asks for, decided from the output's reported RAW formats and the camera's zoom
/// before any `AVCapturePhotoSettings` is built, because an invalid request raises an exception Swift cannot catch.
nonisolated struct PhotoSettingsPlan: Equatable, Sendable {
    /// The Bayer RAW pixel format, or nil for no RAW.
    let rawPixelFormat: OSType?
    let wantsProcessedHEIF: Bool
    /// Bayer RAW requires the speed quality prioritization (AVCapturePhotoOutput.h, Bayer RAW rules), and so does a manual
    /// exposure: balanced prioritization may override the device's ISO and duration (AVCaptureDevice.h, `exposureMode`).
    let prioritizesSpeed: Bool

    /// RAW takes the first Bayer format the output offers (never ProRAW) and needs a zoom factor of exactly 1.0.
    /// While `isExposureManual`, a photo takes the speed prioritization and loses stabilisation and fusion.
    static func make(format: PhotoFormat, availableRawFormats: [OSType], isBayer: (OSType) -> Bool,
                     zoomFactor: Double, isExposureManual: Bool = false) throws(PhotoCaptureError) -> PhotoSettingsPlan {
        guard format.includesRAW else {
            return PhotoSettingsPlan(rawPixelFormat: nil, wantsProcessedHEIF: true, prioritizesSpeed: isExposureManual)
        }
        guard let bayer = availableRawFormats.first(where: isBayer) else { throw .rawUnavailable }
        guard zoomFactor == 1 else { throw .rawNeedsUnitZoom(zoom: zoomFactor) }
        return PhotoSettingsPlan(rawPixelFormat: bayer, wantsProcessedHEIF: format == .rawPlusHEIF, prioritizesSpeed: true)
    }
}
