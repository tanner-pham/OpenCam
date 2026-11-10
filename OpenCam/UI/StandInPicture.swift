import CoreImage
import SwiftUI

/// The Simulator's stand-in scene as a picture, and the same picture with a look applied.
@MainActor enum StandInPicture {
    /// The stand-in without its caption, `size` points at `scale`; nil when it cannot be rendered.
    static func base(size: CGSize, scale: CGFloat) -> CGImage? {
        let renderer = ImageRenderer(content: ViewfinderStandIn(showsCaption: false).frame(width: size.width, height: size.height))
        renderer.scale = scale
        return renderer.cgImage
    }

    /// `base` through the viewfinder's colour table and vignette, at the same size; nil when it cannot be rendered.
    @concurrent static func looked(_ base: CGImage, look: CameraLook) async -> CGImage? {
        let renderer = LookRenderer.shared
        let out = renderer.renderColourAndVignette(CIImage(cgImage: base), cube: LookCompiler.cube(for: look.adjustments), vignette: look.adjustments.vignette)
        return await renderer.cgImage(out)
    }
}
