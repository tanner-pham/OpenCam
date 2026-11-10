import CoreImage
import CoreImage.CIFilterBuiltins
import Metal

/// The one renderer: the editor preview, look tiles, thumbnails, export and the viewfinder all pass through it.
/// Owns the app's only `CIContext`. The colour table is applied in Display P3.
nonisolated final class LookRenderer: Sendable {
    static let shared = LookRenderer()

    /// Metal-backed when a device exists; the default working space (extended linear sRGB).
    let context: CIContext
    let displayP3: CGColorSpace

    /// Long side at which spatial effects are tuned; larger images scale them so proxy and export look alike.
    private static let referenceLongSide: CGFloat = 2048

    private init() {
        if let device = MTLCreateSystemDefaultDevice() {
            context = CIContext(mtlDevice: device)
        } else {
            context = CIContext()
        }
        displayP3 = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
    }

    /// Creates the shared context off the main actor.
    @concurrent static func warmUp() async {
        _ = shared.context
    }

    /// The full pipeline: colour table, then sharpening, noise reduction, grain and vignette. The result keeps `image.extent`.
    func render(_ image: CIImage, adjustments: Adjustments) -> CIImage {
        let extent = image.extent
        let scale = max(1, max(extent.width, extent.height) / Self.referenceLongSide)
        var out = adjustments.hasColourChanges ? applyCube(image, cube: LookCompiler.cube(for: adjustments)) : image
        // Spatial filters sample past the edges, so they read the edge pixels repeated rather than transparency.
        out = out.clampedToExtent()

        if adjustments.sharpening != 0 {
            let filter = CIFilter.sharpenLuminance()
            filter.inputImage = out
            filter.sharpness = Float(0.8 * adjustments.sharpening / 100)
            filter.radius = Float(1.5 * scale)
            out = filter.outputImage ?? out
        }
        if adjustments.noiseReduction != 0 {
            let filter = CIFilter.noiseReduction()
            filter.inputImage = out
            filter.noiseLevel = Float(0.04 * adjustments.noiseReduction / 100)
            filter.sharpness = 0.4
            out = filter.outputImage ?? out
        }
        if adjustments.grain != 0 {
            out = addGrain(to: out, amount: CGFloat(0.12 * adjustments.grain / 100), scale: scale, extent: extent)
        }
        return applyVignette(out, vignette: adjustments.vignette, extent: extent).cropped(to: extent)
    }

    /// The colour table and vignette only, for the viewfinder; matches `render` for the same values.
    func renderColourAndVignette(_ image: CIImage, cube: ColourCube, vignette: Double) -> CIImage {
        let extent = image.extent
        return applyVignette(applyCube(image, cube: cube).clampedToExtent(), vignette: vignette, extent: extent).cropped(to: extent)
    }

    /// Core Image converts the image from the working space into Display P3 for the lookup and back afterwards.
    func applyCube(_ image: CIImage, cube: ColourCube) -> CIImage {
        let filter = CIFilter.colorCubeWithColorSpace()
        filter.inputImage = image
        filter.cubeDimension = Float(cube.dimension)
        filter.cubeData = cube.cubeData
        filter.colorSpace = displayP3
        filter.extrapolate = false
        return filter.outputImage ?? image
    }

    /// Display P3, 8 bits per channel, over the image's extent.
    @concurrent func cgImage(_ image: CIImage) async -> CGImage? {
        context.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: displayP3)
    }

    @concurrent func renderedCGImage(_ image: CIImage, adjustments: Adjustments) async -> CGImage? {
        await cgImage(render(image, adjustments: adjustments))
    }

    /// Monochrome noise centred on zero, enlarged by `scale` with nearest sampling, added to the image.
    private func addGrain(to image: CIImage, amount a: CGFloat, scale: CGFloat, extent: CGRect) -> CIImage {
        let matrix = CIFilter.colorMatrix()
        // The generator's alpha is random too; the matrix would divide the colour by it, so it is set to 1 first.
        matrix.inputImage = CIFilter.randomGenerator().outputImage?.settingAlphaOne(in: .infinite)
        matrix.rVector = CIVector(x: a, y: 0, z: 0, w: 0)
        matrix.gVector = CIVector(x: a, y: 0, z: 0, w: 0)
        matrix.bVector = CIVector(x: a, y: 0, z: 0, w: 0)
        matrix.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        // Alpha comes from the bias: the filter premultiplies its result, so an alpha of 0 would zero the noise.
        matrix.biasVector = CIVector(x: -a / 2, y: -a / 2, z: -a / 2, w: 1)
        guard let noise = matrix.outputImage else { return image }
        let grain = noise.samplingNearest().transformed(by: CGAffineTransform(scaleX: scale, y: scale)).cropped(to: extent)
        let add = CIFilter.additionCompositing()
        add.inputImage = grain
        add.backgroundImage = image
        // The sum's alpha is 2; set it back to 1 without changing the colour.
        return add.outputImage?.settingAlphaOne(in: extent) ?? image
    }

    /// `vignette` is the slider value: negative darkens the corners, positive lightens them.
    private func applyVignette(_ image: CIImage, vignette: Double, extent: CGRect) -> CIImage {
        guard vignette != 0 else { return image }
        let filter = CIFilter.vignetteEffect()
        filter.inputImage = image
        filter.center = CGPoint(x: extent.midX, y: extent.midY)
        filter.radius = Float(0.75 * hypot(extent.width, extent.height) / 2)
        filter.falloff = 0.5
        filter.intensity = Float(-vignette / 100)
        return filter.outputImage ?? image
    }
}
