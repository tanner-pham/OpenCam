import CoreImage
import CoreImage.CIFilterBuiltins
import Metal
import OSLog

/// The one renderer: the editor preview, look tiles, thumbnails, export and the viewfinder all pass through it.
/// Owns the app's only `CIContext`. The colour table is applied in Display P3.
nonisolated final class LookRenderer: Sendable {
    static let shared = LookRenderer()

    private static let logger = Logger(subsystem: "local.opencam.app", category: "LookRenderer")

    /// Metal-backed when a device exists; the default working space (extended linear sRGB).
    let context: CIContext
    let displayP3: CGColorSpace
    /// ITU-R BT.2100 HLG, the space the writer path's frames arrive in.
    let hlg: CGColorSpace
    private let cubes: ColourCubeCache

    /// Long side at which spatial effects are tuned; larger images scale them so proxy and export look alike.
    private static let referenceLongSide: CGFloat = 2048
    /// The table for no colour change. A table equal to it is skipped, so values outside 0...1 are not clipped.
    private static let identityCube = LookCompiler.cube(for: Adjustments())

    /// `cubes` is replaceable for tests; the app uses `shared`.
    init(cubes: ColourCubeCache = ColourCubeCache()) {
        if let device = MTLCreateSystemDefaultDevice() {
            context = CIContext(mtlDevice: device)
        } else {
            context = CIContext()
        }
        displayP3 = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
        hlg = CGColorSpace(name: CGColorSpace.itur_2100_HLG) ?? CGColorSpaceCreateDeviceRGB()
        self.cubes = cubes
    }

    /// Creates the shared context off the main actor.
    @concurrent static func warmUp() async {
        _ = shared.context
    }

    /// The full pipeline: colour table, then sharpening, noise reduction, grain and vignette. The result keeps `image.extent`.
    func render(_ image: CIImage, adjustments: Adjustments) -> CIImage {
        render(image, adjustments: adjustments, cube: adjustments.hasColourChanges ? cubes.cube(for: adjustments) : Self.identityCube)
    }

    /// `render` with a colour table built for this call alone. Look tiles draw many different tables in a row; going through
    /// the one-entry cache would push out the editor preview's table each time.
    func renderWithOwnTable(_ image: CIImage, adjustments: Adjustments) -> CIImage {
        render(image, adjustments: adjustments, cube: adjustments.hasColourChanges ? LookCompiler.cube(for: adjustments) : Self.identityCube)
    }

    private func render(_ image: CIImage, adjustments: Adjustments, cube: ColourCube) -> CIImage {
        let extent = image.extent
        let scale = max(1, max(extent.width, extent.height) / Self.referenceLongSide)
        // Spatial filters sample past the edges, so they read the edge pixels repeated rather than transparency.
        var out = applyColourStage(image, cube: cube).clampedToExtent()

        if adjustments.sharpening != 0 {
            let filter = CIFilter.sharpenLuminance()
            filter.inputImage = out
            filter.sharpness = Float(0.8 * adjustments.sharpening / 100)
            filter.radius = Float(1.5 * scale)
            out = output(of: filter, stage: "sharpening", function: "render") ?? out
        }
        if adjustments.noiseReduction != 0 {
            let filter = CIFilter.noiseReduction()
            filter.inputImage = out
            filter.noiseLevel = Float(0.04 * adjustments.noiseReduction / 100)
            filter.sharpness = 0.4
            out = output(of: filter, stage: "noise reduction", function: "render") ?? out
        }
        if adjustments.grain != 0 {
            out = addGrain(to: out, amount: CGFloat(0.12 * adjustments.grain / 100), scale: scale, extent: extent)
        }
        return applyVignette(out, vignette: adjustments.vignette, extent: extent, function: "render").cropped(to: extent)
    }

    /// The colour table and vignette only, for the viewfinder; matches `render` for the same values.
    func renderColourAndVignette(_ image: CIImage, cube: ColourCube, vignette: Double) -> CIImage {
        let extent = image.extent
        return applyVignette(applyColourStage(image, cube: cube).clampedToExtent(), vignette: vignette, extent: extent, function: "renderColourAndVignette").cropped(to: extent)
    }

    /// Core Image converts the image from the working space into Display P3 for the lookup and back afterwards.
    func applyCube(_ image: CIImage, cube: ColourCube) -> CIImage {
        applyTable(image, cube: cube, in: displayP3)
    }

    /// The same lookup with the table read in `colourSpace`: Core Image converts the image from the working space into it
    /// and back. A table meant for HLG values is applied in HLG, so a highlight is not pushed out of 0...1 by the conversion.
    func applyTable(_ image: CIImage, cube: ColourCube, in colourSpace: CGColorSpace) -> CIImage {
        let filter = CIFilter.colorCubeWithColorSpace()
        filter.inputImage = image
        filter.cubeDimension = Float(cube.dimension)
        filter.cubeData = cube.cubeData
        filter.colorSpace = colourSpace
        filter.extrapolate = false
        return output(of: filter, stage: "colour table", function: "applyTable") ?? image
    }

    /// Display P3, 8 bits per channel, over the image's extent.
    @concurrent func cgImage(_ image: CIImage) async -> CGImage? {
        context.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: displayP3)
    }

    @concurrent func renderedCGImage(_ image: CIImage, adjustments: Adjustments) async -> CGImage? {
        await cgImage(render(image, adjustments: adjustments))
    }

    /// `renderedCGImage` through `renderWithOwnTable`, for look tiles.
    @concurrent func renderedCGImageWithOwnTable(_ image: CIImage, adjustments: Adjustments) async -> CGImage? {
        await cgImage(renderWithOwnTable(image, adjustments: adjustments))
    }

    /// The one rule both entry points use: the no-change table is skipped, any other table is applied.
    /// Comparing against the shared identity table is immediate when it is that same table.
    private func applyColourStage(_ image: CIImage, cube: ColourCube) -> CIImage {
        cube == Self.identityCube ? image : applyCube(image, cube: cube)
    }

    /// Monochrome noise centred on zero, enlarged by `scale` with nearest sampling, added to the Display P3-encoded values
    /// so it reads evenly from shadows to highlights.
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
        guard let noise = output(of: matrix, stage: "grain noise", function: "render") else { return image }
        let grain = noise.samplingNearest().transformed(by: CGAffineTransform(scaleX: scale, y: scale)).cropped(to: extent)
        guard let encoded = image.matchedFromWorkingSpace(to: displayP3) else {
            logDropped(stage: "grain", reason: "conversion to Display P3 failed", function: "render")
            return image
        }
        let add = CIFilter.additionCompositing()
        add.inputImage = grain
        add.backgroundImage = encoded
        guard let sum = output(of: add, stage: "grain", function: "render") else { return image }
        // The sum's alpha is 2; set it back to 1 without changing the colour.
        guard let linear = sum.settingAlphaOne(in: extent).matchedToWorkingSpace(from: displayP3) else {
            logDropped(stage: "grain", reason: "conversion from Display P3 failed", function: "render")
            return image
        }
        return linear
    }

    /// `vignette` is the slider value: negative darkens the corners, positive lightens them.
    private func applyVignette(_ image: CIImage, vignette: Double, extent: CGRect, function: String) -> CIImage {
        guard vignette != 0 else { return image }
        let filter = CIFilter.vignetteEffect()
        filter.inputImage = image
        filter.center = CGPoint(x: extent.midX, y: extent.midY)
        filter.radius = Float(0.75 * hypot(extent.width, extent.height) / 2)
        filter.falloff = 0.5
        filter.intensity = Float(-vignette / 100)
        return output(of: filter, stage: "vignette", function: function) ?? image
    }

    /// The filter's output, or nil after logging that the stage was dropped.
    private func output(of filter: CIFilter, stage: String, function: String) -> CIImage? {
        guard let image = filter.outputImage else {
            logDropped(stage: stage, reason: "\(filter.name) gave no image", function: function)
            return nil
        }
        return image
    }

    private func logDropped(stage: String, reason: String, function: String) {
        Self.logger.error("[LookRenderer:\(function, privacy: .public)] Stage was skipped — {stage: \(stage, privacy: .public), reason: \(reason, privacy: .public)}")
    }
}
