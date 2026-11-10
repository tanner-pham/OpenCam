import CoreGraphics

/// Places a frame in the drawable as `.resizeAspect` places the preview: scaled to fit, centred.
nonisolated enum FrameFit {
    static func aspectFit(_ extent: CGRect, in drawable: CGSize) -> CGAffineTransform {
        guard extent.width > 0, extent.height > 0 else { return .identity }
        let scale = min(drawable.width / extent.width, drawable.height / extent.height)
        let offsetX = (drawable.width - extent.width * scale) / 2
        let offsetY = (drawable.height - extent.height * scale) / 2
        return CGAffineTransform(translationX: -extent.minX, y: -extent.minY)
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: offsetX, y: offsetY))
    }
}
