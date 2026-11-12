import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import Testing
@testable import OpenCam

@Suite struct LookRendererTableTests {
    let renderer = LookRenderer.shared

    /// A flat patch whose channels are these values in HLG.
    func hlgPatch(_ value: Float) throws -> CIImage {
        guard let colour = CIColor(red: CGFloat(value), green: CGFloat(value), blue: CGFloat(value), colorSpace: renderer.hlg) else {
            throw TestFileError.colourUnavailable
        }
        return CIImage(color: colour).cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))
    }

    /// One pixel rendered as RGBA floats in HLG.
    func hlgPixel(_ image: CIImage) -> SIMD3<Float> {
        var pixel = [Float](repeating: 0, count: 4)
        renderer.context.render(image, toBitmap: &pixel, rowBytes: 4 * MemoryLayout<Float>.size, bounds: CGRect(x: 4, y: 4, width: 1, height: 1), format: .RGBAf, colorSpace: renderer.hlg)
        return SIMD3(pixel[0], pixel[1], pixel[2])
    }

    func through(_ cube: ColourCube, _ value: Float) throws -> Float {
        hlgPixel(renderer.applyTable(try hlgPatch(value), cube: cube, in: renderer.hlg)).x
    }

    @Test func aTableInHLGMapsGreyToTheCurveValue() throws {
        #expect(abs(try through(LogProfile.bakeCube(), 0.38) - 0.45) < 0.005)
    }

    @Test func aTableInHLGKeepsPeakWhite() throws {
        #expect(abs(try through(LogProfile.bakeCube(), 1.0) - 0.837) < 0.005)
    }

    @Test func previewAfterBakeReturnsThePicture() throws {
        for value: Float in [0.2, 0.38, 0.75] {
            let baked = renderer.applyTable(try hlgPatch(value), cube: LogProfile.bakeCube(), in: renderer.hlg)
            let back = hlgPixel(renderer.applyTable(baked, cube: LogProfile.previewCube(), in: renderer.hlg)).x
            #expect(abs(back - value) < 0.01, "value \(value)")
        }
    }

    @Test func applyCubeIsUnchanged() throws {
        let look = Adjustments().setting(.exposure, to: 1).setting(.saturation, to: -30)
        let cube = LookCompiler.cube(for: look)
        for input in [SIMD3<Float>(0.2, 0.5, 0.8), SIMD3(1, 0, 0), SIMD3(0.5, 0.5, 0.5)] {
            // The filter exactly as it was set up before the table pass took a colour space.
            let filter = CIFilter.colorCubeWithColorSpace()
            filter.inputImage = try TestFiles.patch(input)
            filter.cubeDimension = Float(cube.dimension)
            filter.cubeData = cube.cubeData
            filter.colorSpace = renderer.displayP3
            filter.extrapolate = false
            let expected = try PixelReader.rgb(try #require(filter.outputImage), x: 4, y: 4)
            let actual = try PixelReader.rgb(renderer.applyCube(try TestFiles.patch(input), cube: cube), x: 4, y: 4)
            #expect(actual == expected)
        }
    }

    @Test func aPerChannelTableOfNothingIsTheLattice() {
        #expect(LookCompiler.cube(perChannel: { $0 }) == LookCompiler.lattice(dimension: ColourCube.standardDimension))
    }

    /// The table is compared with one built by a plain loop over `ColourMath`, entry for entry.
    @Test func aLooksTableIsBitForBitWhatItWas() {
        let look = Adjustments().setting(.exposure, to: 1).setting(.contrast, to: 25).setting(.saturation, to: -30)
        var expected = [Float]()
        for b in 0..<33 {
            for g in 0..<33 {
                for r in 0..<33 {
                    let out = ColourMath.apply(look, to: SIMD3(Float(r) / 32, Float(g) / 32, Float(b) / 32))
                    expected.append(contentsOf: [out.x, out.y, out.z, 1])
                }
            }
        }
        #expect(LookCompiler.cube(for: look).data == expected)
    }
}
