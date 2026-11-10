import Foundation

/// Typed error whose message follows `[Module:Function] description`.
struct ProbeError: Error {
    let site: String
    let detail: String
    var message: String { "[\(site)] \(detail)" }
}

func errorMessage(_ error: Error, site: String) -> String {
    if let probe = error as? ProbeError { return probe.message }
    return "[\(site)] \(error.localizedDescription)"
}

func fourCC(_ value: UInt32) -> String {
    let bytes = [24, 16, 8, 0].map { UInt8((value >> UInt32($0)) & 0xFF) }
    let printable = bytes.allSatisfy { $0 >= 32 && $0 < 127 }
    return printable ? String(decoding: bytes, as: UTF8.self) : "0x" + String(value, radix: 16)
}

struct Report: Codable {
    var summary = Summary()
    var startedAt = Date()
    var finishedAt: Date?
    var device = DeviceInfo()
    var cameras: [CameraInfo] = []
    var encoders: [EncoderInfo] = []
    var audio = AudioInfo()
    var rawTest = RawTestInfo()
    var errors: [String] = []
}

struct Summary: Codable {
    var camerasFound = 0
    var fastestSustainedRawFps: Double?
    var fastestSustainedRawSize: String?
    var fastestSustainedRawMethod: String?
    var appleLogSeen = false
    var appleLog2Seen = false
    var proResInMovieOutputCodecs = false
    var proResRawInMovieOutputCodecs = false
    var bayerOnVideoDataOutput = false
    var cameraControlSupported: Bool?
    var notes: [String] = []
}

struct DeviceInfo: Codable {
    var modelIdentifier = ""
    var systemName = ""
    var osVersion = ""
    var thermalState = ""
    var cameraAuthorization = ""
    var microphoneAuthorization = ""
}

struct CameraInfo: Codable {
    var name = ""
    var uniqueID = ""
    var deviceType = ""
    var position = ""
    var constituentDevices: [String] = []
    var minZoom = 1.0
    var maxZoom = 1.0
    var switchOverZoomFactors: [Double] = []
    var lensAperture: Float = 0
    var bayerRawPhotoPossible: Bool?
    var formats: [FormatInfo] = []
    var outputs = OutputsInfo()
    var errors: [String] = []
}

struct FormatInfo: Codable {
    var index = 0
    var width: Int32 = 0
    var height: Int32 = 0
    var mediaSubtype = ""
    var frameRateRanges: [String] = []
    var colorSpaces: [String] = []
    var videoHDRSupported = false
    var binned = false
    var maxPhotoDimensions: [String] = []
    var bayerRawPhoto: Bool?
    var movieCodecTypes: [String] = []
    var highPhotoQualitySupported = false
    var highestPhotoQualitySupported = false
    var globalToneMappingSupported = false
    var multiCamSupported = false
    var cinematicVideoSupported = false
    var lensApertureRange: String?
    var fieldOfView: Float = 0
    var zoomMax: Double = 0
    var notes: [String] = []
}

struct OutputsInfo: Codable {
    var rawPhotoPixelFormats: [PixelFormatInfo] = []
    var appleProRAWSupported: Bool?
    var photoCodecTypes: [String] = []
    var maxPhotoDimensions: String?
    var maxBracketedCapturePhotoCount: Int?
    var movieCodecTypes: [String] = []
    var movieCodecTypesAcrossFormats: [String] = []
    var videoDataPixelFormats: [PixelFormatInfo] = []
    var videoDataCodecsForAssetWriter: [String: [String]] = [:]
    var bayerVideoFormats: [BayerVideoHit] = []
    var supportsControls: Bool?
    var maxControlsCount: Int?
    var errors: [String] = []
}

struct PixelFormatInfo: Codable {
    var fourCC: String
    var isBayer: Bool
    var isProRAW: Bool
}

/// A format on which the video data output offers a Bayer or versatile Bayer pixel format.
struct BayerVideoHit: Codable {
    var formatIndex: Int
    var width: Int32
    var height: Int32
    var mediaSubtype: String
    var bayerFormats: [String]
}

struct EncoderInfo: Codable {
    var codecType = ""
    var encoderID = ""
    var name = ""
    var displayName = ""
    var hardwareAccelerated: Bool?
    var isProResFamily = false
}

struct AudioInfo: Codable {
    var inputs: [AudioPortInfo] = []
    var outputs: [AudioPortInfo] = []
    var errors: [String] = []
}

struct AudioPortInfo: Codable {
    var name = ""
    var portType = ""
    var dataSources: [AudioDataSourceInfo] = []
}

struct AudioDataSourceInfo: Codable {
    var name = ""
    var supportedPolarPatterns: [String] = []
    var selectedPolarPattern: String?
}

struct RawTestInfo: Codable {
    var cameraName: String?
    var format: String?
    var runs: [RawRun] = []
    var sustainedRun: RawRun?
    var errors: [String] = []
}

struct RawRun: Codable {
    var method = ""
    var seconds: Double = 0
    var framesDelivered = 0
    var fps: Double = 0
    var avgIntervalMs: Double?
    var worstIntervalMs: Double?
    var rawWidth: Int32?
    var rawHeight: Int32?
    var bitDepth: Int?
    var thermalBefore = ""
    var thermalAfter = ""
    var errors: [String] = []
}
