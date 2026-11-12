import AVFoundation

/// Reads a finished movie back the way any player would: the video track's codec, size, rate and colour description.
nonisolated enum RecorderCheckReadback {
    static func read(_ url: URL) async -> RecorderCheckFileFacts {
        var facts = RecorderCheckFileFacts()
        do {
            facts.fileBytes = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize.map(Int64.init)
        } catch {
            facts.readError = RecorderCheck.logError("read", "The file size could not be read", context: "reason: \(error.localizedDescription)")
        }
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            facts.durationSeconds = duration.isNumeric ? duration.seconds : nil
            guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                facts.readError = "The file has no video track"
                return facts
            }
            let (size, rate, descriptions) = try await track.load(.naturalSize, .nominalFrameRate, .formatDescriptions)
            facts.naturalWidth = Double(size.width)
            facts.naturalHeight = Double(size.height)
            facts.nominalFrameRate = Double(rate)
            guard let description = descriptions.first else { return facts }
            facts.codec = RecorderCheckFourCC.string(CMFormatDescriptionGetMediaSubType(description))
            facts.colourPrimaries = Self.text(description, kCMFormatDescriptionExtension_ColorPrimaries)
            facts.transferFunction = Self.text(description, kCMFormatDescriptionExtension_TransferFunction)
            facts.yCbCrMatrix = Self.text(description, kCMFormatDescriptionExtension_YCbCrMatrix)
            facts.bitsPerComponent = Self.text(description, kCMFormatDescriptionExtension_BitsPerComponent).flatMap { Int($0) }
        } catch {
            facts.readError = RecorderCheck.logError("read", "The file could not be read back", context: "reason: \(error.localizedDescription)")
        }
        return facts
    }

    private static func text(_ description: CMFormatDescription, _ key: CFString) -> String? {
        CMFormatDescriptionGetExtension(description, extensionKey: key).map { String(describing: $0) }
    }
}
