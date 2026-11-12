import CoreVideo

/// A cheap mean luma from a sparse grid of the Y plane, 0 (black) to 1 (white), for the formats the check asks for.
nonisolated enum RecorderCheck2Luma {
    private static let gridSide = 16

    /// Nil for a format this does not read (for example a compressed one).
    static func mean(of buffer: CVPixelBuffer) -> Double? {
        let format = CVPixelBufferGetPixelFormatType(buffer)
        // (bytes per sample, shift to the code value, black, white)
        let layout: (bytes: Int, shift: Int, black: Double, white: Double)
        switch format {
        case kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange: layout = (2, 6, 64, 940)
        case kCVPixelFormatType_420YpCbCr10BiPlanarFullRange: layout = (2, 6, 0, 1023)
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange: layout = (1, 0, 16, 235)
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange: layout = (1, 0, 0, 255)
        default: return nil
        }
        guard CVPixelBufferGetPlaneCount(buffer) > 0, CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else { return nil }
        let width = CVPixelBufferGetWidthOfPlane(buffer, 0), height = CVPixelBufferGetHeightOfPlane(buffer, 0)
        let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        guard width > gridSide, height > gridSide else { return nil }
        var sum = 0.0
        for row in 0..<gridSide {
            let y = (row * 2 + 1) * height / (gridSide * 2)
            for column in 0..<gridSide {
                let x = (column * 2 + 1) * width / (gridSide * 2)
                let offset = y * rowBytes + x * layout.bytes
                let raw = layout.bytes == 2 ? Int(UnsafeRawPointer(base).loadUnaligned(fromByteOffset: offset, as: UInt16.self)) >> layout.shift
                                            : Int(UnsafeRawPointer(base).loadUnaligned(fromByteOffset: offset, as: UInt8.self))
                sum += min(max((Double(raw) - layout.black) / (layout.white - layout.black), 0), 1)
            }
        }
        return sum / Double(gridSide * gridSide)
    }
}
