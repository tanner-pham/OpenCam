import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox

typealias Log = @Sendable (String) -> Void

/// Sections 1 to 5. Every function is synchronous and records failures as data.
enum Inventory {
    static func thermalName(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }

    static func authName(_ status: AVAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: "notDetermined"
        case .restricted: "restricted"
        case .denied: "denied"
        case .authorized: "authorized"
        @unknown default: "unknown"
        }
    }

    // MARK: Device

    static func device() -> DeviceInfo {
        var info = DeviceInfo()
        var systemInfo = utsname()
        uname(&systemInfo)
        info.modelIdentifier = withUnsafeBytes(of: &systemInfo.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        let os = ProcessInfo.processInfo
        info.systemName = "iOS"
        info.osVersion = os.operatingSystemVersionString
        info.thermalState = thermalName(os.thermalState)
        info.cameraAuthorization = authName(AVCaptureDevice.authorizationStatus(for: .video))
        info.microphoneAuthorization = authName(AVCaptureDevice.authorizationStatus(for: .audio))
        return info
    }

    // MARK: Cameras

    static func discover() -> [AVCaptureDevice] {
        let types: [AVCaptureDevice.DeviceType] = [
            .builtInWideAngleCamera, .builtInTelephotoCamera, .builtInUltraWideCamera,
            .builtInOuterUltraWideCamera, .builtInInnerUltraWideCamera,
            .builtInDualCamera, .builtInDualWideCamera, .builtInTripleCamera,
            .builtInTrueDepthCamera, .builtInLiDARDepthCamera,
            .continuityCamera, .external,
        ]
        var seen = Set<String>()
        var found: [AVCaptureDevice] = []
        for position in [AVCaptureDevice.Position.back, .front, .unspecified] {
            let session = AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: position)
            for device in session.devices where seen.insert(device.uniqueID).inserted {
                found.append(device)
            }
        }
        return found
    }

    static func positionName(_ position: AVCaptureDevice.Position) -> String {
        switch position {
        case .back: "back"
        case .front: "front"
        case .unspecified: "unspecified"
        @unknown default: "unknown(\(position.rawValue))"
        }
    }

    static func colorSpaceName(_ space: AVCaptureColorSpace) -> String {
        switch space {
        case .sRGB: "sRGB"
        case .P3_D65: "P3_D65"
        case .HLG_BT2020: "HLG_BT2020"
        case .appleLog: "AppleLog"
        case .appleLog2: "AppleLog2"
        @unknown default: "unknown(\(space.rawValue))"
        }
    }

    static func isBayer(_ pixelFormat: OSType) -> Bool {
        AVCapturePhotoOutput.isBayerRAWPixelFormat(pixelFormat)
            || pixelFormat == kCVPixelFormatType_16VersatileBayer
            || pixelFormat == kCVPixelFormatType_96VersatileBayerPacked12
    }

    static func isBayerVideo(_ pixelFormat: OSType) -> Bool {
        let bayer14: [OSType] = [
            kCVPixelFormatType_14Bayer_GRBG, kCVPixelFormatType_14Bayer_RGGB,
            kCVPixelFormatType_14Bayer_BGGR, kCVPixelFormatType_14Bayer_GBRG,
        ]
        return bayer14.contains(pixelFormat) || isBayer(pixelFormat)
    }

    static func describe(_ format: AVCaptureDevice.Format, index: Int) -> FormatInfo {
        var info = FormatInfo()
        info.index = index
        let description = format.formatDescription
        info.width = description.dimensions.width
        info.height = description.dimensions.height
        info.mediaSubtype = fourCC(description.mediaSubType.rawValue)
        info.frameRateRanges = format.videoSupportedFrameRateRanges.map { "\($0.minFrameRate)-\($0.maxFrameRate)" }
        info.colorSpaces = format.supportedColorSpaces.map(colorSpaceName)
        info.videoHDRSupported = format.isVideoHDRSupported
        info.binned = format.isVideoBinned
        info.maxPhotoDimensions = format.supportedMaxPhotoDimensions.map { "\($0.width)x\($0.height)" }
        info.highPhotoQualitySupported = format.isHighPhotoQualitySupported
        info.highestPhotoQualitySupported = format.isHighestPhotoQualitySupported
        info.globalToneMappingSupported = format.isGlobalToneMappingSupported
        info.multiCamSupported = format.isMultiCamSupported
        info.cinematicVideoSupported = format.isCinematicVideoCaptureSupported
        info.lensApertureRange = "\(format.minLensAperture)-\(format.maxLensAperture) default \(format.defaultLensAperture)"
        info.fieldOfView = format.videoFieldOfView
        info.zoomMax = Double(format.videoMaxZoomFactor)
        if format.isVideoStabilizationModeSupported(.cinematicExtended) { info.notes.append("cinematicExtendedStabilization") }
        // The SDK exposes no per-format Log, ProRes or ProRes RAW flag: Log shows in colorSpaces,
        // ProRes and RAW show in the output codec lists and pixel formats.
        return info
    }

    static func cameras(log: Log) -> [CameraInfo] {
        var results: [CameraInfo] = []
        for device in discover() {
            log("Camera: \(device.localizedName)")
            var info = CameraInfo()
            info.name = device.localizedName
            info.uniqueID = device.uniqueID
            info.deviceType = device.deviceType.rawValue
            info.position = positionName(device.position)
            info.constituentDevices = device.constituentDevices.map { "\($0.localizedName) [\($0.deviceType.rawValue)]" }
            info.minZoom = Double(device.minAvailableVideoZoomFactor)
            info.maxZoom = Double(device.maxAvailableVideoZoomFactor)
            info.switchOverZoomFactors = device.virtualDeviceSwitchOverVideoZoomFactors.map { $0.doubleValue }
            info.lensAperture = device.lensAperture
            info.formats = device.formats.enumerated().map { describe($1, index: $0) }
            scanOutputs(of: device, into: &info)
            results.append(info)
        }
        return results
    }

    // MARK: Outputs

    /// Configures a throwaway session per camera, walks every format and reads output capabilities.
    static func scanOutputs(of device: AVCaptureDevice, into info: inout CameraInfo) {
        let session = AVCaptureSession()
        let photo = AVCapturePhotoOutput()
        let movie = AVCaptureMovieFileOutput()
        let video = AVCaptureVideoDataOutput()
        let originalFormat = device.activeFormat
        defer {
            session.beginConfiguration()
            session.inputs.forEach { session.removeInput($0) }
            session.outputs.forEach { session.removeOutput($0) }
            session.commitConfiguration()
            restore(originalFormat, on: device)
        }
        do {
            let input = try AVCaptureDeviceInput(device: device)
            session.beginConfiguration()
            guard session.canAddInput(input) else {
                throw ProbeError(site: "Inventory:scanOutputs", detail: "session cannot add input for \(device.localizedName)")
            }
            session.addInput(input)
            if session.canAddOutput(photo) { session.addOutput(photo) } else { info.outputs.errors.append("[Inventory:scanOutputs] cannot add photo output") }
            if session.canAddOutput(movie) { session.addOutput(movie) } else { info.outputs.errors.append("[Inventory:scanOutputs] cannot add movie output") }
            if session.canAddOutput(video) { session.addOutput(video) } else { info.outputs.errors.append("[Inventory:scanOutputs] cannot add video data output") }
            session.commitConfiguration()
        } catch {
            info.outputs.errors.append(errorMessage(error, site: "Inventory:scanOutputs"))
            return
        }

        var out = info.outputs
        out.supportsControls = session.supportsControls
        out.maxControlsCount = session.maxControlsCount
        out.appleProRAWSupported = photo.isAppleProRAWSupported
        if let largest = device.activeFormat.supportedMaxPhotoDimensions.max(by: { Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height) }) {
            photo.maxPhotoDimensions = largest
        }
        out.maxPhotoDimensions = "\(photo.maxPhotoDimensions.width)x\(photo.maxPhotoDimensions.height)"

        var bayerPhotoAnywhere = false
        var movieUnion = Set<String>()
        for (index, format) in device.formats.enumerated() {
            guard setActive(format, on: device) else {
                out.errors.append("[Inventory:scanOutputs] could not select format \(index)")
                continue
            }
            let rawFormats = photo.availableRawPhotoPixelFormatTypes.map { $0 }
            let hasBayerPhoto = rawFormats.contains { AVCapturePhotoOutput.isBayerRAWPixelFormat($0) }
            let movieCodecs = movie.availableVideoCodecTypes.map(\.rawValue)
            movieUnion.formUnion(movieCodecs)
            if index < info.formats.count {
                info.formats[index].bayerRawPhoto = hasBayerPhoto
                info.formats[index].movieCodecTypes = movieCodecs
            }
            bayerPhotoAnywhere = bayerPhotoAnywhere || hasBayerPhoto
            let videoFormats = video.availableVideoPixelFormatTypes
            let bayerVideo = videoFormats.filter(isBayerVideo)
            if !bayerVideo.isEmpty {
                let dims = format.formatDescription.dimensions
                out.bayerVideoFormats.append(BayerVideoHit(
                    formatIndex: index, width: dims.width, height: dims.height,
                    mediaSubtype: fourCC(format.formatDescription.mediaSubType.rawValue),
                    bayerFormats: bayerVideo.map(fourCC)))
            }
        }
        info.bayerRawPhotoPossible = bayerPhotoAnywhere
        out.movieCodecTypesAcrossFormats = movieUnion.sorted()

        // Default-format readings.
        restore(originalFormat, on: device)
        out.rawPhotoPixelFormats = photo.availableRawPhotoPixelFormatTypes.map {
            PixelFormatInfo(fourCC: fourCC($0), isBayer: AVCapturePhotoOutput.isBayerRAWPixelFormat($0),
                            isProRAW: AVCapturePhotoOutput.isAppleProRAWPixelFormat($0))
        }
        out.photoCodecTypes = photo.availablePhotoCodecTypes.map(\.rawValue)
        out.maxBracketedCapturePhotoCount = Int(photo.maxBracketedCapturePhotoCount)
        out.movieCodecTypes = movie.availableVideoCodecTypes.map(\.rawValue)
        out.videoDataPixelFormats = video.availableVideoPixelFormatTypes.map {
            PixelFormatInfo(fourCC: fourCC($0), isBayer: isBayerVideo($0), isProRAW: false)
        }
        for fileType in [AVFileType.mov, .mp4] {
            out.videoDataCodecsForAssetWriter[fileType.rawValue] =
                video.availableVideoCodecTypesForAssetWriter(writingTo: fileType).map(\.rawValue)
        }
        info.outputs = out
    }

    @discardableResult
    static func setActive(_ format: AVCaptureDevice.Format, on device: AVCaptureDevice) -> Bool {
        do {
            try device.lockForConfiguration()
            device.activeFormat = format
            device.unlockForConfiguration()
            return true
        } catch {
            return false
        }
    }

    static func restore(_ format: AVCaptureDevice.Format, on device: AVCaptureDevice) {
        setActive(format, on: device)
    }

    // MARK: Encoders

    static func encoders() throws -> [EncoderInfo] {
        var list: CFArray?
        let status = VTCopyVideoEncoderList(nil, &list)
        guard status == noErr, let entries = list as? [[String: Any]] else {
            throw ProbeError(site: "Inventory:encoders", detail: "VTCopyVideoEncoderList failed, OSStatus \(status)")
        }
        let proRes: Set<String> = ["apch", "apcn", "apcs", "apco", "ap4h", "ap4x", "aprn", "aprh"]
        return entries.map { entry in
            var info = EncoderInfo()
            if let code = entry[kVTVideoEncoderList_CodecType as String] as? NSNumber { info.codecType = fourCC(code.uint32Value) }
            info.encoderID = entry[kVTVideoEncoderList_EncoderID as String] as? String ?? ""
            info.name = entry[kVTVideoEncoderList_EncoderName as String] as? String ?? ""
            info.displayName = entry[kVTVideoEncoderList_DisplayName as String] as? String ?? ""
            info.hardwareAccelerated = entry[kVTVideoEncoderList_IsHardwareAccelerated as String] as? Bool
            info.isProResFamily = proRes.contains(info.codecType)
            return info
        }
    }

    // MARK: Audio

    static func audio() -> AudioInfo {
        var info = AudioInfo()
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default)
        } catch {
            info.errors.append(errorMessage(error, site: "Inventory:audio"))
        }
        func port(_ description: AVAudioSessionPortDescription) -> AudioPortInfo {
            var port = AudioPortInfo(name: description.portName, portType: description.portType.rawValue)
            port.dataSources = (description.dataSources ?? []).map {
                AudioDataSourceInfo(name: $0.dataSourceName,
                                    supportedPolarPatterns: ($0.supportedPolarPatterns ?? []).map(\.rawValue),
                                    selectedPolarPattern: $0.selectedPolarPattern?.rawValue)
            }
            return port
        }
        info.inputs = (session.availableInputs ?? []).map(port)
        info.outputs = session.currentRoute.outputs.map(port)
        return info
    }
}
