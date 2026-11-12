import Foundation

/// The baked profile: a log encoding of the scene light the HLG signal stands for, per channel on BT.2020 R'G'B'.
/// code = slope * log2(x + offset) + C, with x = 0.18 * sceneLight / (sceneLight of mid grey), and C chosen so mid grey
/// lands on `greyCode`.
nonisolated enum LogProfile {
    /// An 18 percent grey card in HLG (ITU-R BT.2408).
    static let greySignal = 0.38
    static let greyCode = 0.45
    /// Code values per stop where the curve is logarithmic.
    static let slope = 0.09
    static let offset = 0.01
    /// The code for an HLG signal of 0.
    static let blackCode = slope * log2(offset) + intercept
    /// The code for an HLG signal of 1.
    static let peakCode = encode(signal: 1)

    private static let greyLight = HLGCurve.sceneLight(signal: greySignal)
    private static let greyReflectance = 0.18
    private static let intercept = greyCode - slope * log2(greyReflectance + offset)

    /// HLG signal 0...1 to Log code.
    static func encode(signal: Double) -> Double {
        let x = greyReflectance * HLGCurve.sceneLight(signal: signal) / greyLight
        return slope * log2(x + offset) + intercept
    }

    /// Log code to HLG signal; 0 at and below `blackCode`; not clamped above `peakCode`, so the preview table has no corner there.
    static func decode(code: Double) -> Double {
        guard code > blackCode else { return 0 }
        let x = exp2((code - intercept) / slope) - offset
        return HLGCurve.signal(sceneLight: max(x, 0) * greyLight / greyReflectance)
    }

    /// 33 points, `encode` on each channel.
    static func bakeCube() -> ColourCube {
        LookCompiler.cube { Float(encode(signal: Double($0))) }
    }

    /// 33 points, `decode` on each channel.
    static func previewCube() -> ColourCube {
        LookCompiler.cube { Float(decode(code: Double($0))) }
    }
}
