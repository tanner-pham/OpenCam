import CoreMedia

/// A pixel size, as the check reports it.
nonisolated struct RawSizeCheckSize: Codable, Sendable, Hashable {
    var width: Int
    var height: Int

    var pixels: Int { width * height }
    var label: String { "\(width) x \(height)" }

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    init(_ dimensions: CMVideoDimensions) {
        self.init(width: Int(dimensions.width), height: Int(dimensions.height))
    }

    /// The same size as AVFoundation's type.
    var dimensions: CMVideoDimensions { CMVideoDimensions(width: Int32(clamping: width), height: Int32(clamping: height)) }

    /// A size AVFoundation leaves at 0 x 0 when it has none.
    var isEmpty: Bool { width == 0 || height == 0 }

    /// What the app's own RAW photos have measured on the phone.
    static let twelveMegapixel = RawSizeCheckSize(width: 4032, height: 3024)
}
