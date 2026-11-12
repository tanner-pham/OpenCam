import CoreGraphics

/// 256-bin counts of a rendered picture's encoded Display P3 values, for the curve editor to draw behind the curve.
nonisolated struct PictureHistogram: Sendable, Equatable {
    static let binCount = 256
    static let sampleLongSide = 256

    let luma: [UInt32]
    let red: [UInt32]
    let green: [UInt32]
    let blue: [UInt32]

    /// Counts RGBA8 bytes (alpha ignored). Luma bin: `Int((0.2126·r + 0.7152·g + 0.0722·b).rounded())`, on the encoded bytes.
    static func counting(rgba: [UInt8]) -> PictureHistogram {
        var luma = [UInt32](repeating: 0, count: binCount)
        var red = luma, green = luma, blue = luma
        var index = 0
        while index + 3 < rgba.count {
            let r = Int(rgba[index]), g = Int(rgba[index + 1]), b = Int(rgba[index + 2])
            red[r] += 1
            green[g] += 1
            blue[b] += 1
            let weighted = (0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)).rounded()
            luma[min(binCount - 1, Int(weighted))] += 1
            index += 4
        }
        return PictureHistogram(luma: luma, red: red, green: green, blue: blue)
    }

    /// Draws `image` into an RGBA8 Display P3 bitmap whose long side is at most `sampleLongSide`, then counts it. Nil when the
    /// bitmap cannot be made. The preview is already Display P3 and encoded, so the bins are the values the curve's x axis shows.
    @concurrent static func make(from image: CGImage) async -> PictureHistogram? {
        let longSide = max(image.width, image.height)
        guard longSide > 0, let space = CGColorSpace(name: CGColorSpace.displayP3) else { return nil }
        let scale = min(1, Double(sampleLongSide) / Double(longSide))
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let isDrawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return isDrawn ? counting(rgba: bytes) : nil
    }

    /// count / peak, capped at 1; peak is the largest count over bins 1...254 of all four channels (at least 1), so a clipped
    /// spike at 0 or 255 does not flatten the rest.
    func heights(_ channel: HistogramChannel) -> [Double] {
        let peak = max(1, [luma, red, green, blue].map { $0[1...254].max() ?? 0 }.max() ?? 0)
        let counts: [UInt32]
        switch channel {
        case .luma: counts = luma
        case .red: counts = red
        case .green: counts = green
        case .blue: counts = blue
        }
        return counts.map { min(1, Double($0) / Double(peak)) }
    }
}
