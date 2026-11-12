/// One trial of the second check: a size, rate and codec, with or without the colour table pass.
nonisolated struct RecorderCheck2Plan: Sendable {
    let target: RecorderCheckTarget
    let codec: RecorderCheckCodec
    let usesColourPass: Bool

    var label: String {
        let size = target.height == 2160 ? "4K" : "\(target.height)p"
        let name: String
        switch codec {
        case .hevc: name = "HEVC"
        case .proResProxy: name = "ProRes 422 Proxy"
        case .proResLT: name = "ProRes 422 LT"
        case .proRes422: name = "ProRes 422"
        case .proResHQ: name = "ProRes 422 HQ"
        }
        return "\(size) \(target.framesPerSecond) \(name)" + (usesColourPass ? " with colour table" : "")
    }

    private static let uhd30 = RecorderCheckTarget(width: 3840, height: 2160, framesPerSecond: 30)
    private static let uhd60 = RecorderCheckTarget(width: 3840, height: 2160, framesPerSecond: 60)

    /// The six trials, hardest last.
    static let all = [
        RecorderCheck2Plan(target: uhd30, codec: .proResHQ, usesColourPass: false),
        RecorderCheck2Plan(target: uhd60, codec: .proRes422, usesColourPass: false),
        RecorderCheck2Plan(target: uhd60, codec: .proResHQ, usesColourPass: false),
        RecorderCheck2Plan(target: uhd30, codec: .hevc, usesColourPass: true),
        RecorderCheck2Plan(target: uhd30, codec: .proResHQ, usesColourPass: true),
        RecorderCheck2Plan(target: uhd60, codec: .proResHQ, usesColourPass: true),
    ]
}
