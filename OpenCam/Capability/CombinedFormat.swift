import Foundation

/// One video format of the combined back camera.
nonisolated struct CombinedFormat: Sendable, Equatable {
    let width: Int
    let height: Int
    /// `AVCaptureColorSpace` raw values.
    let colourSpaces: [Int]
    let frameRateRanges: [ClosedRange<Double>]
    let maxZoomFactor: Double
}
