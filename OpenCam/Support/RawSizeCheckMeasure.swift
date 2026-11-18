import Foundation
import ImageIO

/// Reads the pixel size of every image in a photo's data, in memory.
nonisolated enum RawSizeCheckMeasure {
    static func photo(isRaw: Bool, data: Data) -> RawSizeCheckPhoto {
        let sizes = imageSizes(in: data)
        return RawSizeCheckPhoto(isRaw: isRaw, size: sizes.max { $0.pixels < $1.pixels }, imageSizes: sizes, bytes: data.count)
    }

    static func imageSizes(in data: Data) -> [RawSizeCheckSize] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return [] }
        return (0..<CGImageSourceGetCount(source)).compactMap { index in
            guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
            return RawSizeCheckSize(width: width, height: height)
        }
    }
}
