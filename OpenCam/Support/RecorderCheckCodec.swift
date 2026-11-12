import AVFoundation

/// The codecs the writer trials compare. HEVC is the hardware baseline; the ProRes types are software encoders.
nonisolated enum RecorderCheckCodec: CaseIterable, Sendable {
    case hevc, proResProxy, proResLT, proRes422, proResHQ

    var type: AVVideoCodecType {
        switch self {
        case .hevc: .hevc
        case .proResProxy: .proRes422Proxy
        case .proResLT: .proRes422LT
        case .proRes422: .proRes422
        case .proResHQ: .proRes422HQ
        }
    }

    var label: String {
        switch self {
        case .hevc: "HEVC (hardware baseline)"
        case .proResProxy: "ProRes 422 Proxy"
        case .proResLT: "ProRes 422 LT"
        case .proRes422: "ProRes 422"
        case .proResHQ: "ProRes 422 HQ"
        }
    }

    /// Every ProRes type, 4444 included, for the question of what the data output offers.
    static let allProResTypes: [AVVideoCodecType] = [.proRes422Proxy, .proRes422LT, .proRes422, .proRes422HQ, .proRes4444, .appleProRes4444XQ]
}
