import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins

/// The grayscale image a local mask blends through: white where its adjustments apply fully, black where they do not.
nonisolated enum MaskImage {
    /// Long side, in pixels, of the bitmap a brush mask is painted into.
    private static let brushLongSide: CGFloat = 1024
    private static let brushBlur: Double = 2

    /// A grayscale image over `extent`, inverted when `mask.isInverted`. Nil when the mask cannot apply: degenerate geometry, a
    /// brush with nothing painted, or a subject mask without a subject. `subject` is a mask of the subject, white on it, at any scale.
    /// Geometry is clamped here, the one place it is read.
    static func image(for mask: LocalMask, extent: CGRect, subject: CIImage?) -> CIImage? {
        guard extent.width > 0, extent.height > 0, extent.width.isFinite, extent.height.isFinite else { return nil }
        let base: CIImage?
        switch mask.shape {
        case let .linear(start, end): base = linear(start: start, end: end, extent: extent)
        case let .radial(centre, radius, feather): base = radial(centre: centre, radius: radius, feather: feather, extent: extent)
        case let .brush(strokes): base = brush(strokes: strokes, extent: extent)
        case .subject: base = subject.flatMap { fit($0, to: extent) }
        }
        guard let base else { return nil }
        guard mask.isInverted else { return base }
        let invert = CIFilter.colorInvert()
        invert.inputImage = base
        return invert.outputImage?.cropped(to: extent)
    }

    private static func isUsable(_ values: Double...) -> Bool { values.allSatisfy(\.isFinite) }

    private static func clampedPoint(_ point: MaskPoint) -> MaskPoint {
        MaskPoint(x: min(max(point.x, -1), 2), y: min(max(point.y, -1), 2))
    }

    /// Picture coordinates (0...1 from the top left) to Core Image coordinates in `extent`.
    private static func location(of point: MaskPoint, in extent: CGRect) -> CGPoint {
        CGPoint(x: extent.minX + point.x * extent.width, y: extent.minY + (1 - point.y) * extent.height)
    }

    private static func linear(start: MaskPoint, end: MaskPoint, extent: CGRect) -> CIImage? {
        guard isUsable(start.x, start.y, end.x, end.y) else { return nil }
        let from = location(of: clampedPoint(start), in: extent), to = location(of: clampedPoint(end), in: extent)
        guard hypot(to.x - from.x, to.y - from.y) > 1e-3 else { return nil }
        let filter = CIFilter.linearGradient()
        filter.point0 = from
        filter.point1 = to
        filter.color0 = .white
        filter.color1 = .black
        return filter.outputImage?.cropped(to: extent)
    }

    private static func radial(centre: MaskPoint, radius: Double, feather: Double, extent: CGRect) -> CIImage? {
        guard isUsable(centre.x, centre.y, radius, feather), radius > 0 else { return nil }
        let short = min(extent.width, extent.height)
        let outer = min(max(radius, 0.001), 4) * short
        let inner = min(outer * (1 - min(max(feather, 0), 1)), outer - 0.5)
        let filter = CIFilter.radialGradient()
        filter.center = location(of: clampedPoint(centre), in: extent)
        filter.radius0 = Float(max(inner, 0))
        filter.radius1 = Float(outer)
        filter.color0 = .white
        filter.color1 = .black
        return filter.outputImage?.cropped(to: extent)
    }

    /// Strokes painted in order into a bitmap of at most `brushLongSide`, then scaled to `extent` and softened a little.
    private static func brush(strokes: [BrushStroke], extent: CGRect) -> CIImage? {
        guard strokes.contains(where: { !$0.isErasing && !$0.dabs.isEmpty }) else { return nil }
        let scale = min(1, brushLongSide / max(extent.width, extent.height))
        let width = max(1, Int((extent.width * scale).rounded())), height = max(1, Int((extent.height * scale).rounded()))
        let short = CGFloat(min(width, height))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setLineCap(.round)
        context.setLineJoin(.round)
        for stroke in strokes {
            let tone: CGFloat = stroke.isErasing ? 0 : 1
            context.setFillColor(gray: tone, alpha: 1)
            context.setStrokeColor(gray: tone, alpha: 1)
            var previous: CGPoint?
            for dab in stroke.dabs where isUsable(dab.x, dab.y, dab.radius) {
                let point = clampedPoint(MaskPoint(x: dab.x, y: dab.y))
                // The bitmap, like Core Image, has y up; the picture's y runs down.
                let centre = CGPoint(x: point.x * CGFloat(width), y: (1 - point.y) * CGFloat(height))
                let radius = min(max(dab.radius, 0.001), 0.5) * short
                context.fillEllipse(in: CGRect(x: centre.x - radius, y: centre.y - radius, width: 2 * radius, height: 2 * radius))
                if let previous {
                    context.setLineWidth(2 * radius)
                    context.move(to: previous)
                    context.addLine(to: centre)
                    context.strokePath()
                }
                previous = centre
            }
        }
        guard let bitmap = context.makeImage() else { return nil }
        let painted = CIImage(cgImage: bitmap)
        let soft = CIFilter.gaussianBlur()
        soft.inputImage = painted.clampedToExtent()
        soft.radius = Float(brushBlur)
        guard let blurred = soft.outputImage?.cropped(to: painted.extent) else { return nil }
        return fit(blurred, to: extent)
    }

    /// `image` scaled and moved to cover `extent` exactly.
    private static func fit(_ image: CIImage, to extent: CGRect) -> CIImage? {
        let source = image.extent
        guard source.width > 0, source.height > 0, source.width.isFinite, source.height.isFinite else { return nil }
        let transform = CGAffineTransform(translationX: -source.minX, y: -source.minY)
            .concatenating(CGAffineTransform(scaleX: extent.width / source.width, y: extent.height / source.height))
            .concatenating(CGAffineTransform(translationX: extent.minX, y: extent.minY))
        return image.transformed(by: transform).cropped(to: extent)
    }
}
