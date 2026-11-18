/// One photo of a capture, measured from its data in memory. Nothing is written to disk.
nonisolated struct RawSizeCheckPhoto: Codable, Sendable, Equatable {
    var isRaw: Bool
    /// The largest image in the file's data, read with ImageIO; nil when the data could not be read as an image.
    var size: RawSizeCheckSize?
    /// Every image ImageIO finds in the data (the picture, and any preview or thumbnail).
    var imageSizes: [RawSizeCheckSize]
    var bytes: Int
}
