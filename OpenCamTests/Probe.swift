import Foundation
import Testing
@testable import OpenCam

nonisolated struct Probe: Sendable, CustomTestStringConvertible {
    let key: AdjustmentKey; let rgb: SIMD3<Float>; let channel: Int; let rises: Bool
    var testDescription: String { "\(key) channel \(channel)" }
}
