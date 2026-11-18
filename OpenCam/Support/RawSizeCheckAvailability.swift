/// What the photo output offered after a size was set.
nonisolated struct RawSizeCheckAvailability: Codable, Sendable, Equatable {
    var maxPhotoDimensionsSet: RawSizeCheckSize
    var rawPixelFormats: [RawSizeCheckRawFormat]
    var rawFileTypes: [String]
    var isAppleProRAWSupported: Bool
    var isAppleProRAWEnabled: Bool
    var maxPhotoQualityPrioritization: Int

    var hasBayer: Bool { rawPixelFormats.contains { $0.kind == "bayer" } }
}
