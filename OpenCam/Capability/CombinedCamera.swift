import Foundation

/// The back camera that holds several lenses and changes between them without a new camera input.
nonisolated struct CombinedCamera: Sendable, Equatable {
    let deviceUniqueID: String
    /// The zoom at which each of its cameras takes over, by that camera's unique ID: 1 for the first, then the switch-over factors.
    let baseZoomByDeviceID: [String: Double]
    let formats: [CombinedFormat]

    /// Nil unless this camera can record `video` through `lens`: video mode, a lens it holds, and a format with the option's
    /// size, colour space and frame rate (the 0.05 tolerance `StandardFrameRates.collapse` uses) whose zoom reaches the lens's.
    func lens(for lens: Lens, mode: CaptureMode, video: VideoOption?) -> CombinedLens? {
        guard mode == .video, let video, let base = baseZoomByDeviceID[lens.deviceUniqueID] else { return nil }
        let zoom = base * lens.zoomFactor
        let colourSpace = video.colour.captureColorSpaceRawValue
        let rate = Double(video.frameRate)
        let isServed = formats.contains { format in
            format.width == video.resolution.width && format.height == video.resolution.height
                && format.colourSpaces.contains(colourSpace)
                && format.frameRateRanges.contains { $0.lowerBound - 0.05 <= rate && rate <= $0.upperBound + 0.05 }
                && format.maxZoomFactor >= zoom
        }
        return isServed ? CombinedLens(deviceUniqueID: deviceUniqueID, zoomFactor: zoom) : nil
    }
}
