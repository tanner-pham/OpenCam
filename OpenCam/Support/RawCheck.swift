import AVFoundation
import OSLog

/// A one-off diagnostic, reached only with the `-rawCheck` launch argument. The capability scan reads RAW support on a
/// stopped session; this asks RUNNING sessions that hold nothing but a photo output, with the photo preset and with the
/// phone's best photo format chosen by hand, and writes what they offer to `Documents/raw-check.json`.
nonisolated enum RawCheck {
    nonisolated struct Reading: Codable, Sendable {
        var camera: String
        var deviceType: String
        var position: String
        var setup: String
        var isRunning = false
        var activeFormat = ""
        var maxPhotoDimensions = ""
        var rawPixelFormatsBeforeRunning: [String] = []
        var rawPixelFormats: [String] = []
        var bayerFormats: [String] = []
        var proRAWFormats: [String] = []
        var rawFileTypes: [String] = []
        var isAppleProRAWSupported = false
        var rawPixelFormatsWithProRAWEnabled: [String] = []
        var photoCodecs: [String] = []
        var errors: [String] = []
    }

    nonisolated struct Report: Codable, Sendable {
        var takenAt: Date
        var osVersion: String
        var readings: [Reading]
    }

    private static let logger = Logger(subsystem: "local.opencam.app", category: "RawCheck")
    static let fileName = "raw-check.json"

    /// Runs off the main actor: starting a session blocks.
    @concurrent static func runAndWrite() async {
        let report = run()
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let directory = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            try encoder.encode(report).write(to: directory.appending(path: fileName), options: .atomic)
        } catch {
            logger.error("[RawCheck:runAndWrite] The report could not be written — {reason: \(error.localizedDescription, privacy: .public)}")
        }
    }

    static func run() -> Report {
        let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .builtInUltraWideCamera],
                                                         mediaType: .video, position: .unspecified)
        var readings: [Reading] = []
        for device in discovery.devices where device.position == .back {
            for setup in Setup.allCases { readings.append(read(device, setup: setup)) }
        }
        return Report(takenAt: .now, osVersion: ProcessInfo.processInfo.operatingSystemVersionString, readings: readings)
    }

    nonisolated enum Setup: String, CaseIterable, Sendable {
        case photoPreset = "photo preset"
        case photoPresetWithDataOutput = "photo preset + video data output"
        case inputPriorityFullRange = "input priority, best photo format, full range"
        case inputPriorityVideoRange = "input priority, best photo format, video range"

        var usesPreset: Bool { self == .photoPreset || self == .photoPresetWithDataOutput }
    }

    /// One session with a photo output, read once stopped and once running. The input-priority setups pick, by hand, the
    /// format with the largest photo size among those that support the highest photo quality.
    private static func read(_ device: AVCaptureDevice, setup: Setup) -> Reading {
        var reading = Reading(camera: device.localizedName, deviceType: device.deviceType.rawValue,
                              position: positionName(device.position), setup: setup.rawValue)
        let session = AVCaptureSession()
        let photo = AVCapturePhotoOutput()
        session.beginConfiguration()
        session.sessionPreset = setup.usesPreset ? .photo : .inputPriority
        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input), session.canAddOutput(photo) else {
                session.commitConfiguration()
                reading.errors.append("[RawCheck:read] The session cannot take this camera with a photo output")
                return reading
            }
            session.addInput(input)
            session.addOutput(photo)
            if setup == .photoPresetWithDataOutput {
                let data = AVCaptureVideoDataOutput()
                if session.canAddOutput(data) { session.addOutput(data) } else { reading.errors.append("[RawCheck:read] The data output could not be added") }
            }
            if !setup.usesPreset, let format = bestPhotoFormat(of: device, fullRange: setup == .inputPriorityFullRange) {
                try device.lockForConfiguration()
                device.activeFormat = format
                device.unlockForConfiguration()
            }
        } catch {
            session.commitConfiguration()
            reading.errors.append("[RawCheck:read] Camera input failed — {reason: \(error.localizedDescription)}")
            return reading
        }
        session.commitConfiguration()
        reading.rawPixelFormatsBeforeRunning = photo.availableRawPhotoPixelFormatTypes.map(fourCC)
        session.startRunning()
        // Long enough for a running session to publish what its output supports.
        Thread.sleep(forTimeInterval: 1.5)
        reading.isRunning = session.isRunning

        let active = device.activeFormat
        let size = active.formatDescription.dimensions
        reading.activeFormat = "\(size.width)x\(size.height) \(fourCC(active.formatDescription.mediaSubType.rawValue))"
        if let largest = active.supportedMaxPhotoDimensions.max(by: { Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height) }) {
            photo.maxPhotoDimensions = largest
        }
        reading.maxPhotoDimensions = "\(photo.maxPhotoDimensions.width)x\(photo.maxPhotoDimensions.height)"

        let raw = photo.availableRawPhotoPixelFormatTypes
        reading.rawPixelFormats = raw.map(fourCC)
        reading.bayerFormats = raw.filter { AVCapturePhotoOutput.isBayerRAWPixelFormat($0) }.map(fourCC)
        reading.proRAWFormats = raw.filter { AVCapturePhotoOutput.isAppleProRAWPixelFormat($0) }.map(fourCC)
        reading.rawFileTypes = photo.availableRawPhotoFileTypes.map(\.rawValue)
        reading.photoCodecs = photo.availablePhotoCodecTypes.map(\.rawValue)
        reading.isAppleProRAWSupported = photo.isAppleProRAWSupported
        if photo.isAppleProRAWSupported {
            photo.isAppleProRAWEnabled = true
            reading.rawPixelFormatsWithProRAWEnabled = photo.availableRawPhotoPixelFormatTypes.map(fourCC)
        }
        session.stopRunning()
        return reading
    }

    private static func bestPhotoFormat(of device: AVCaptureDevice, fullRange: Bool) -> AVCaptureDevice.Format? {
        func pixels(_ format: AVCaptureDevice.Format) -> Int {
            format.supportedMaxPhotoDimensions.map { Int($0.width) * Int($0.height) }.max() ?? 0
        }
        let wanted = fullRange ? kCVPixelFormatType_420YpCbCr8BiPlanarFullRange : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        return device.formats
            .filter { $0.isHighestPhotoQualitySupported && $0.formatDescription.mediaSubType.rawValue == wanted }
            .max { pixels($0) < pixels($1) }
    }

    private static func positionName(_ position: AVCaptureDevice.Position) -> String {
        switch position {
        case .back: "back"
        case .front: "front"
        default: "unspecified"
        }
    }

    private static func fourCC(_ code: OSType) -> String {
        let bytes = [UInt8(code >> 24 & 0xFF), UInt8(code >> 16 & 0xFF), UInt8(code >> 8 & 0xFF), UInt8(code & 0xFF)]
        guard bytes.allSatisfy({ $0 >= 32 && $0 < 127 }) else { return String(code) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
