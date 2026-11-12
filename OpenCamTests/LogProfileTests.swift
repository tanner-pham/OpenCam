import Foundation
import Testing
@testable import OpenCam

@Suite struct LogProfileTests {
    /// HLG signal and the Log code it must give (the plan's reference table).
    static let reference: [(signal: Double, code: Double)] = [
        (0, 0.067687), (0.10, 0.172780), (0.20, 0.300033), (0.38, 0.450000),
        (0.50, 0.518348), (0.75, 0.665745), (0.90, 0.767171), (1.00, 0.837240),
    ]

    /// Value of the table's nodes by linear interpolation, for a signal in 0...1.
    func interpolated(_ cube: ColourCube, at value: Double) -> Double {
        let scaled = min(max(value, 0), 1) * Double(cube.dimension - 1)
        let low = min(Int(scaled), cube.dimension - 2)
        let fraction = scaled - Double(low)
        // Grey diagonal, red channel.
        func node(_ i: Int) -> Double { Double(cube.data[((i * cube.dimension + i) * cube.dimension + i) * 4]) }
        return node(low) * (1 - fraction) + node(low + 1) * fraction
    }

    @Test func referenceValues() {
        for row in Self.reference { #expect(abs(LogProfile.encode(signal: row.signal) - row.code) < 1e-5, "signal \(row.signal)") }
        #expect(abs(LogProfile.encode(signal: LogProfile.greySignal) - LogProfile.greyCode) < 1e-12)
        #expect(abs(LogProfile.blackCode - 0.067687) < 1e-5)
        #expect(abs(LogProfile.peakCode - 0.837240) < 1e-5)
    }

    @Test func encodeIsMonotonic() {
        var previous = LogProfile.encode(signal: 0)
        for step in 1...1000 {
            let code = LogProfile.encode(signal: Double(step) / 1000)
            #expect(code > previous, "step \(step)")
            previous = code
        }
    }

    @Test func theFormulasRoundTrip() {
        for step in 0...1000 {
            let signal = Double(step) / 1000
            #expect(abs(LogProfile.decode(code: LogProfile.encode(signal: signal)) - signal) < 1e-6, "signal \(signal)")
        }
    }

    @Test func decodeIsZeroAtAndBelowBlackAndNotClampedAbovePeak() {
        #expect(LogProfile.decode(code: LogProfile.blackCode) == 0)
        #expect(LogProfile.decode(code: 0) == 0)
        #expect(LogProfile.decode(code: LogProfile.peakCode + 0.05) > 1)
    }

    @Test func theBakeTableFollowsTheCurve() {
        let cube = LogProfile.bakeCube()
        #expect(cube.dimension == 33)
        for step in 0...1000 {
            let signal = Double(step) / 1000
            #expect(abs(interpolated(cube, at: signal) - LogProfile.encode(signal: signal)) < 0.004, "signal \(signal)")
        }
    }

    @Test func bakeThenPreviewReturnsThePicture() {
        let bake = LogProfile.bakeCube(), preview = LogProfile.previewCube()
        #expect(preview.dimension == 33)
        for step in 0...1000 {
            let signal = Double(step) / 1000
            let back = interpolated(preview, at: interpolated(bake, at: signal))
            #expect(abs(back - signal) < (signal < 0.05 ? 0.008 : 0.001), "signal \(signal)")
        }
    }

    @Test func eachChannelIsEncodedOnItsOwn() {
        let cube = LogProfile.bakeCube()
        func at(_ r: Int, _ g: Int, _ b: Int) -> [Float] { let i = ((b * 33 + g) * 33 + r) * 4; return Array(cube.data[i..<i + 4]) }
        let colour = at(32, 16, 0)
        #expect(abs(Double(colour[0]) - LogProfile.peakCode) < 1e-5)
        #expect(abs(Double(colour[1]) - LogProfile.encode(signal: 0.5)) < 1e-5)
        #expect(abs(Double(colour[2]) - LogProfile.blackCode) < 1e-5)
        #expect(colour[3] == 1)
    }

    @Test func hlgCurveMatchesBT2100() {
        #expect(abs(HLGCurve.sceneLight(signal: 0.5) - 1.0 / 12) < 1e-12)
        #expect(abs(HLGCurve.sceneLight(signal: 0.75) - 0.264963) < 1e-6)
        #expect(abs(HLGCurve.sceneLight(signal: 1) - 1) < 1e-6)
        for step in 0...1000 {
            let signal = Double(step) / 1000
            #expect(abs(HLGCurve.signal(sceneLight: HLGCurve.sceneLight(signal: signal)) - signal) < 1e-9, "signal \(signal)")
        }
        #expect(abs(HLGCurve.signal(sceneLight: 1) - 1) < 1e-6)
    }
}
