import Foundation

/// The Simulator has no camera, so manual controls need something to show and to move: values a phone could report.
nonisolated enum SimulatedCamera {
    /// Video holds a 180 degree shutter at the frame rate; photo is a daylight exposure.
    static func readouts(mode: CaptureMode, frameRate: Int) -> LiveReadouts {
        switch mode {
        case .video:
            LiveReadouts(iso: 200, shutterSeconds: 1 / Double(2 * max(frameRate, 1)), kelvin: 5600, tint: 0, exposureBias: 0, lensPosition: 0.4)
        case .photo:
            LiveReadouts(iso: 100, shutterSeconds: 1.0 / 125, kelvin: 5200, tint: 4, exposureBias: 0, lensPosition: 0.35)
        }
    }

    /// Video's longest shutter is the frame time, as on the device.
    static func ranges(mode: CaptureMode, frameRate: Int) -> ManualRanges {
        let frame = 1 / Double(max(frameRate, 1))
        return ManualRanges(
            shutterSeconds: (1.0 / 8000)...(mode == .video ? frame : 1),
            iso: 25...3200,
            bias: -2...2,
            hasWhiteBalance: true,
            hasFocus: true,
            frameSeconds: mode == .video ? frame : nil
        )
    }
}
