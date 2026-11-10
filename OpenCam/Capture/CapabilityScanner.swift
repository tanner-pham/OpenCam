import AVFoundation
import OSLog

/// Asks each camera what it can record, modelled on the probe's `Inventory.scanOutputs`.
/// Each camera gets a throwaway session with photo and movie outputs; the output lists follow the device's active format.
/// Photo sizes and RAW come from one more throwaway session on the photo preset (`presetReading`).
nonisolated enum CapabilityScanner {
    private static let logger = Logger(subsystem: "local.opencam.app", category: "CapabilityScanner")

    /// Runs on the concurrent executor, never the caller's actor. A zoomed lens shares its camera, so only unzoomed lenses are scanned.
    /// A camera that cannot be added or configured is logged and skipped; the scan throws only when no camera gave a format.
    @concurrent
    static func scan(lenses: [Lens]) async throws(CameraSessionError) -> [FormatDescriptor] {
        var descriptors: [FormatDescriptor] = []
        var firstError: CameraSessionError?
        for lens in lenses where lens.zoomFactor == 1 {
            do throws(CameraSessionError) {
                descriptors += try scan(lens)
            } catch {
                logger.error("\(error.description, privacy: .public)")
                firstError = firstError ?? error
            }
        }
        if descriptors.isEmpty, let firstError { throw firstError }
        return descriptors
    }

    /// Photo sizes and RAW come from the photo preset reading when there is one: only under the preset does the camera
    /// offer Bayer RAW (measured on the Duo, 2026-11-10). Without a reading the format walk's own photo fields stay.
    private static func scan(_ lens: Lens) throws(CameraSessionError) -> [FormatDescriptor] {
        guard let device = AVCaptureDevice(uniqueID: lens.deviceUniqueID) else {
            throw .deviceMissing(lensID: lens.id)
        }
        let reading = presetReading(of: device, lensID: lens.id)
        return PhotoPresetReading.assign(reading, to: try walkFormats(of: device, lens: lens))
    }

    /// A throwaway session holding only the camera and a photo output, as measured, on the photo preset and committed,
    /// never started. The preset picks the active format at the commit (AVCaptureSession.h, beginConfiguration: changes
    /// "will be pended until the client calls [session commitConfiguration]"), so everything is read after it.
    /// Nil, logged, when the session cannot take the camera or the preset.
    private static func presetReading(of device: AVCaptureDevice, lensID: String) -> PhotoPresetReading? {
        let session = AVCaptureSession()
        let photo = AVCapturePhotoOutput()
        session.beginConfiguration()
        guard let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
            session.commitConfiguration()
            logger.error("[CapabilityScanner:presetReading] Cannot add input — {lens: \(lensID, privacy: .public)}")
            return nil
        }
        session.addInput(input)
        defer {
            session.beginConfiguration()
            session.inputs.forEach { session.removeInput($0) }
            session.outputs.forEach { session.removeOutput($0) }
            session.commitConfiguration()
        }
        guard session.canAddOutput(photo) else {
            session.commitConfiguration()
            logger.error("[CapabilityScanner:presetReading] Cannot add output — {lens: \(lensID, privacy: .public), name: photo}")
            return nil
        }
        session.addOutput(photo)
        guard session.canSetSessionPreset(.photo) else {
            session.commitConfiguration()
            logger.error("[CapabilityScanner:presetReading] The photo preset cannot be set — {lens: \(lensID, privacy: .public)}")
            return nil
        }
        session.sessionPreset = .photo
        session.commitConfiguration()

        let format = device.activeFormat
        let dimensions = format.formatDescription.dimensions
        var sizes: [PhotoSize] = []
        for size in format.supportedMaxPhotoDimensions {
            let photoSize = PhotoSize(width: Int(size.width), height: Int(size.height))
            if !sizes.contains(photoSize) { sizes.append(photoSize) }
        }
        return PhotoPresetReading(width: Int(dimensions.width), height: Int(dimensions.height), sizes: sizes,
                                  hasBayerRAW: photo.availableRawPhotoPixelFormatTypes.contains { AVCapturePhotoOutput.isBayerRAWPixelFormat($0) })
    }

    private static func walkFormats(of device: AVCaptureDevice, lens: Lens) throws(CameraSessionError) -> [FormatDescriptor] {
        let session = AVCaptureSession()
        // Each colour space is set by hand below; the session would otherwise override it.
        session.automaticallyConfiguresCaptureDeviceForWideColor = false
        let photo = AVCapturePhotoOutput()
        let movie = AVCaptureMovieFileOutput()
        try attach(device, photo: photo, movie: movie, to: session, lensID: lens.id)
        defer {
            session.beginConfiguration()
            session.inputs.forEach { session.removeInput($0) }
            session.outputs.forEach { session.removeOutput($0) }
            session.commitConfiguration()
        }

        do {
            try device.lockForConfiguration()
        } catch {
            throw .lockFailed(reason: String(describing: error))
        }
        let originalFormat = device.activeFormat
        let originalColorSpace = device.activeColorSpace
        defer {
            device.activeFormat = originalFormat
            if originalFormat.supportedColorSpaces.contains(originalColorSpace) {
                device.activeColorSpace = originalColorSpace
            }
            device.unlockForConfiguration()
        }

        return formatClasses(of: device).map { formatClass in
            let format = formatClass.representative
            device.activeFormat = format
            var codecTypesByColourSpace: [Int: [String]] = [:]
            for space in format.supportedColorSpaces {
                device.activeColorSpace = space
                codecTypesByColourSpace[space.rawValue] = movie.availableVideoCodecTypes.map(\.rawValue)
            }
            let settingsKeys = movie.connection(with: .video).map { movie.supportedOutputSettingsKeys(for: $0) } ?? []
            let dimensions = format.formatDescription.dimensions
            return FormatDescriptor(
                lensID: lens.id,
                width: Int(dimensions.width),
                height: Int(dimensions.height),
                isBinned: format.isVideoBinned,
                frameRateRanges: format.videoSupportedFrameRateRanges.map { $0.minFrameRate...$0.maxFrameRate },
                codecTypesByColourSpace: codecTypesByColourSpace,
                allowsCompressionProperties: settingsKeys.contains(AVVideoCompressionPropertiesKey),
                maxPhotoDimensions: formatClass.photoSizes,
                hasBayerRAW: photo.availableRawPhotoPixelFormatTypes.contains { AVCapturePhotoOutput.isBayerRAWPixelFormat($0) }
            )
        }
    }

    private static func attach(
        _ device: AVCaptureDevice, photo: AVCapturePhotoOutput, movie: AVCaptureMovieFileOutput,
        to session: AVCaptureSession, lensID: String
    ) throws(CameraSessionError) {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        guard let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
            throw .cannotAddInput(lensID: lensID)
        }
        session.addInput(input)
        guard session.canAddOutput(photo) else { throw .cannotAddOutput(name: "photo") }
        session.addOutput(photo)
        guard session.canAddOutput(movie) else { throw .cannotAddOutput(name: "movie") }
        session.addOutput(movie)
        // As in CameraSession: the device's activeFormat dictates quality and the session never changes it.
        if session.canSetSessionPreset(.inputPriority) {
            session.sessionPreset = .inputPriority
        }
    }

    /// Formats that share dimensions, colour spaces and frame-rate ranges report the same codecs, so one stands for each class.
    /// The representative is the first unbinned member; photo sizes are the union over the class.
    private static func formatClasses(of device: AVCaptureDevice) -> [(representative: AVCaptureDevice.Format, photoSizes: [PhotoSize])] {
        var classes: [(dimensions: [Int], spaces: [Int], ranges: [ClosedRange<Double>], members: [AVCaptureDevice.Format])] = []
        for format in device.formats {
            let raw = format.formatDescription.dimensions
            let dimensions = [Int(raw.width), Int(raw.height)]
            let spaces = format.supportedColorSpaces.map(\.rawValue).sorted()
            let ranges = format.videoSupportedFrameRateRanges.map { $0.minFrameRate...$0.maxFrameRate }
            if let index = classes.firstIndex(where: { $0.dimensions == dimensions && $0.spaces == spaces && $0.ranges == ranges }) {
                classes[index].members.append(format)
            } else {
                classes.append((dimensions, spaces, ranges, [format]))
            }
        }
        return classes.compactMap { formatClass in
            guard let representative = formatClass.members.first(where: { !$0.isVideoBinned }) ?? formatClass.members.first else { return nil }
            var sizes: [PhotoSize] = []
            for member in formatClass.members {
                for dimensions in member.supportedMaxPhotoDimensions {
                    let size = PhotoSize(width: Int(dimensions.width), height: Int(dimensions.height))
                    if !sizes.contains(size) { sizes.append(size) }
                }
            }
            return (representative, sizes)
        }
    }
}
