import Foundation

nonisolated enum ColourMode: String, Codable, Sendable, Hashable, CaseIterable {
    case rec709 = "Rec. 709"
    case p3 = "P3"
    case hlg = "HLG"
    /// The baked profile: a log curve made from HLG frames. It records in HLG's capture colour space and is never read back from one.
    case log = "Log"
    case appleLog = "Apple Log"
    case appleLog2 = "Apple Log 2"

    /// Maps the raw value of a capture colour space (AVCaptureDevice.h, `AVCaptureColorSpace`). The two directions are
    /// written out side by side; `CameraSession` derives its colour space from `captureColorSpaceRawValue`.
    init?(captureColorSpace rawValue: Int) {
        switch rawValue {
        case 0: self = .rec709      // AVCaptureColorSpace_sRGB
        case 1: self = .p3          // AVCaptureColorSpace_P3_D65
        case 2: self = .hlg         // AVCaptureColorSpace_HLG_BT2020
        case 3: self = .appleLog    // AVCaptureColorSpace_AppleLog
        case 4: self = .appleLog2   // AVCaptureColorSpace_AppleLog2
        default: return nil
        }
    }

    /// The raw value of the capture colour space this colour records in; the reverse of `init?(captureColorSpace:)`.
    var captureColorSpaceRawValue: Int {
        switch self {
        case .rec709: 0
        case .p3: 1
        case .hlg, .log: 2
        case .appleLog: 3
        case .appleLog2: 4
        }
    }

    var shortName: String {
        switch self {
        case .rec709: "Rec. 709"
        case .p3: "P3"
        case .hlg: "HLG"
        case .log: "Log"
        case .appleLog: "Apple Log"
        case .appleLog2: "Apple Log 2"
        }
    }
}
