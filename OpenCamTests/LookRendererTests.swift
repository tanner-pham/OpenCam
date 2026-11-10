import CoreImage
import Foundation
import Testing
@testable import OpenCam

@Suite struct LookRendererTests {
    let renderer = LookRenderer.shared
    func diff(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float { ((a - b) * (a - b)).squareRoot().max() }

    @Test func identityCubeKeepsPixelsSoTheDataOrderIsRight() throws {
        let input = SIMD3<Float>(0.2, 0.5, 0.8)
        let out = renderer.applyCube(try TestFiles.patch(input), cube: LookCompiler.lattice(dimension: 33))
        #expect(diff(try PixelReader.rgb(out, x: 4, y: 4), input) < 2e-3)
    }
    @Test func displayP3RedSurvivesTheColourTable() throws {   // an sRGB table would clip it to about (0.92, 0.20, 0.14)
        let red = SIMD3<Float>(1, 0, 0)
        #expect(diff(try PixelReader.rgb(renderer.applyCube(try TestFiles.patch(red), cube: LookCompiler.lattice(dimension: 33)), x: 4, y: 4), red) < 2e-3)
    }
    @Test func identityAdjustmentsReturnTheSamePixels() throws {
        for input in [SIMD3<Float>(0.2, 0.5, 0.8), SIMD3(1, 0, 0), SIMD3(0.5, 0.5, 0.5)] {
            #expect(diff(try PixelReader.rgb(renderer.render(TestFiles.patch(input), adjustments: Adjustments()), x: 4, y: 4), input) < 2e-3)
        }
    }
    @Test func plusOneStopOnMidGreyMatchesColourMath() throws {
        let a = Adjustments().setting(.exposure, to: 1)
        let out = try PixelReader.rgb(renderer.render(TestFiles.patch(SIMD3(repeating: 0.5)), adjustments: a), x: 4, y: 4)
        #expect(diff(out, ColourMath.apply(a, to: SIMD3(repeating: 0.5))) < 3e-3)
    }
    @Test func saturationMinus100GivesEqualChannels() throws {
        let out = try PixelReader.rgb(renderer.render(TestFiles.patch(SIMD3(0.8, 0.4, 0.2)), adjustments: Adjustments().setting(.saturation, to: -100)), x: 4, y: 4)
        #expect(abs(out.x - out.y) < 2e-3); #expect(abs(out.y - out.z) < 2e-3); #expect(abs(out.x - 0.4706) < 3e-3)
    }
    @Test func vignetteChangesCornersNotTheCentre() throws {
        let grey = try TestFiles.patch(SIMD3(repeating: 0.5), size: 256)
        let dark = renderer.render(grey, adjustments: Adjustments().setting(.vignette, to: -100))
        let light = renderer.render(grey, adjustments: Adjustments().setting(.vignette, to: 100))
        #expect(try PixelReader.rgb(dark, x: 1, y: 1).x < 0.4); #expect(try PixelReader.rgb(light, x: 1, y: 1).x > 0.6)
        #expect(abs(try PixelReader.rgb(dark, x: 128, y: 128).x - 0.5) < 0.02)
    }
    /// The noise texture is fixed, so this is deterministic; it is tested by its statistics rather than exact values.
    @Test func grainAddsZeroMeanNoise() throws {
        let grain = renderer.render(try TestFiles.patch(SIMD3(repeating: 0.5), size: 256), adjustments: Adjustments().setting(.grain, to: 100))
        var values: [Float] = []
        for x in stride(from: 0, to: 256, by: 7) {
            for y in stride(from: 0, to: 256, by: 7) { values.append(try PixelReader.rgb(grain, x: x, y: y).x) }
        }
        let mean = values.reduce(0, +) / Float(values.count)
        let deviation = (values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Float(values.count)).squareRoot()
        #expect(abs(mean - 0.5) < 0.01); #expect(deviation > 0.02); #expect(deviation < 0.06)
        #expect((values.max() ?? 1) < 0.6); #expect((values.min() ?? 0) > 0.4)
    }
    /// Grain is added to Display P3-encoded values, so a dark patch gets the same spread as mid grey, not several times more.
    @Test func grainIsEvenInTheShadows() throws {
        let mid = try grainStatistics(level: 0.5), dark = try grainStatistics(level: 0.1)
        #expect(abs(dark.mean - 0.1) < 0.01)
        #expect(dark.deviation > 0.02); #expect(dark.deviation / mid.deviation > 0.7); #expect(dark.deviation / mid.deviation < 1.4)
    }
    func grainStatistics(level: Float) throws -> (mean: Float, deviation: Float) {
        let grain = renderer.render(try TestFiles.patch(SIMD3(repeating: level), size: 256), adjustments: Adjustments().setting(.grain, to: 100))
        var values: [Float] = []
        for x in stride(from: 0, to: 256, by: 7) {
            for y in stride(from: 0, to: 256, by: 7) { values.append(try PixelReader.rgb(grain, x: x, y: y).x) }
        }
        let mean = values.reduce(0, +) / Float(values.count)
        return (mean, (values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Float(values.count)).squareRoot())
    }
    /// Without colour changes both paths skip the table, so a value above 1 survives in each and they still match.
    @Test func viewfinderPathMatchesWithoutColourChanges() throws {
        let space = try #require(CGColorSpace(name: CGColorSpace.extendedDisplayP3))
        let colour = try #require(CIColor(red: 1.3, green: 0.5, blue: 0.2, colorSpace: space))
        let bright = CIImage(color: colour).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64))
        let vignetteOnly = Adjustments().setting(.vignette, to: 30)
        let full = try PixelReader.rgb(renderer.render(bright, adjustments: vignetteOnly), x: 32, y: 32)
        let viewfinder = try PixelReader.rgb(renderer.renderColourAndVignette(bright, cube: LookCompiler.cube(for: vignetteOnly), vignette: 30), x: 32, y: 32)
        #expect(full.x > 1.1)
        #expect(diff(full, viewfinder) < 1e-3)
    }
    @Test func sameColourAdjustmentsBuildTheTableOnce() throws {
        let builds = CallCounter()
        let counted = LookRenderer(cubes: ColourCubeCache { builds.increment(); return LookCompiler.cube(for: $0) })
        let image = try TestFiles.patch(SIMD3(0.6, 0.4, 0.3))
        let colour = Adjustments().setting(.exposure, to: 0.5)
        _ = counted.render(image, adjustments: colour)
        _ = counted.render(image, adjustments: colour.setting(.sharpening, to: 40).setting(.vignette, to: -20))
        #expect(builds.value == 1)
        _ = counted.render(image, adjustments: colour.setting(.contrast, to: 10))
        #expect(builds.value == 2)
        _ = counted.render(image, adjustments: Adjustments().setting(.grain, to: 30))
        #expect(builds.value == 2)   // no colour change: no table at all
    }
    @Test func spatialStepsKeepTheExtentAndViewfinderPathMatches() throws {
        let image = try TestFiles.patch(SIMD3(0.6, 0.4, 0.3), size: 64)
        let all = Adjustments().setting(.sharpening, to: 50).setting(.noiseReduction, to: 50).setting(.grain, to: 50).setting(.vignette, to: -30)
        #expect(renderer.render(image, adjustments: all).extent == image.extent)
        let colour = Adjustments().setting(.temperature, to: 40).setting(.vignette, to: -30)
        let full = try PixelReader.rgb(renderer.render(image, adjustments: colour), x: 10, y: 10)
        let viewfinder = try PixelReader.rgb(renderer.renderColourAndVignette(image, cube: LookCompiler.cube(for: colour), vignette: -30), x: 10, y: 10)
        #expect(diff(full, viewfinder) < 1e-3)
    }
}
