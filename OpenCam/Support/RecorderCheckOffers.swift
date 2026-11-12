import AVFoundation

/// Report section A: what the video data output offers on the back wide camera, per size and rate, and under the photo preset.
/// The lists are read from a running session, the way a recorder would meet them, after a short wait.
nonisolated enum RecorderCheckOffers {
    private static let settleTime = Duration.milliseconds(800)

    @concurrent static func collect() async -> (offers: [RecorderCheckOffer], preset: RecorderCheckPresetOffer) {
        var offers: [RecorderCheckOffer] = []
        for target in RecorderCheckTarget.all {
            offers.append(await offer(for: target))
        }
        return (offers, await presetOffer())
    }

    private static func offer(for target: RecorderCheckTarget) async -> RecorderCheckOffer {
        var offer = RecorderCheckOffer(target: target.label)
        guard let device = RecorderCheckRig.backWideCamera() else {
            offer.skipReason = RecorderCheck.logError("offer", "No back wide camera", context: "target: \(target.label)")
            return offer
        }
        guard let chosen = RecorderCheckFormats.pick(on: device, for: target) else {
            offer.skipReason = RecorderCheck.logError("offer", "No camera format at this size and rate", context: "target: \(target.label)")
            return offer
        }
        offer.format = chosen.pick
        let rig: RecorderCheckRig
        do {
            rig = try RecorderCheckRig(device: device, preset: .inputPriority)
            rig.requestFullSizeBuffers()
            try rig.apply(format: chosen.format, target: target)
        } catch {
            offer.skipReason = RecorderCheck.logError("offer", "The session could not be set up", context: "target: \(target.label), reason: \(RecorderCheck.describe(error))")
            return offer
        }
        offer.activeColorSpace = RecorderCheckFormats.colorSpaceName(device.activeColorSpace)
        rig.session.startRunning()
        offer.wasSessionRunning = rig.session.isRunning
        try? await Task.sleep(for: settleTime)

        let output = rig.output
        offer.pixelFormats = output.availableVideoPixelFormatTypes.map(RecorderCheckFourCC.string)
        offer.videoCodecTypes = output.availableVideoCodecTypes.map(\.rawValue)
        let writerCodecs = output.availableVideoCodecTypesForAssetWriter(writingTo: .mov)
        offer.assetWriterCodecTypesForMov = writerCodecs.map(\.rawValue)
        offer.currentVideoSettings = RecorderCheckDescribe.value(output.videoSettings ?? [:])
        for type in RecorderCheckCodec.allProResTypes + [.hevc] {
            guard writerCodecs.contains(type) else {
                offer.recommendedSettings[type.rawValue] = "not asked: the codec is not in the asset-writer list for .mov"
                continue
            }
            if let settings = output.recommendedVideoSettings(forVideoCodecType: type, assetWriterOutputFileType: .mov) {
                offer.recommendedSettings[type.rawValue] = RecorderCheckDescribe.value(settings)
            } else {
                offer.recommendedSettings[type.rawValue] = "nil"
            }
        }
        rig.session.stopRunning()
        return offer
    }

    private static func presetOffer() async -> RecorderCheckPresetOffer {
        var offer = RecorderCheckPresetOffer()
        guard let device = RecorderCheckRig.backWideCamera() else {
            offer.skipReason = RecorderCheck.logError("presetOffer", "No back wide camera", context: "preset: photo")
            return offer
        }
        let rig: RecorderCheckRig
        do {
            rig = try RecorderCheckRig(device: device, preset: .photo)
        } catch {
            offer.skipReason = RecorderCheck.logError("presetOffer", "The session could not be set up", context: "reason: \(RecorderCheck.describe(error))")
            return offer
        }
        rig.session.startRunning()
        offer.wasSessionRunning = rig.session.isRunning
        try? await Task.sleep(for: settleTime)
        let active = device.activeFormat
        let size = active.formatDescription.dimensions
        offer.activeFormat = "\(size.width)x\(size.height) \(RecorderCheckFourCC.string(active.formatDescription.mediaSubType.rawValue))"
        let formats = rig.output.availableVideoPixelFormatTypes
        offer.pixelFormats = formats.map(RecorderCheckFourCC.string)
        offer.bayerPixelFormats = formats.filter { AVCapturePhotoOutput.isBayerRAWPixelFormat($0) }.map(RecorderCheckFourCC.string)
        offer.videoCodecTypes = rig.output.availableVideoCodecTypes.map(\.rawValue)
        rig.session.stopRunning()
        return offer
    }
}
