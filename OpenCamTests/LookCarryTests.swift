import CoreImage
import Foundation
import Testing
@testable import OpenCam

nonisolated struct LookCarryTests {
    func maxDiff(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float { ((a - b) * (a - b)).squareRoot().max() }
    static var curveOnly: Adjustments {
        var a = Adjustments(); a.curves.master = ToneCurve(points: [CurvePoint(x: 0, y: 0), CurvePoint(x: 0.5, y: 0.6), CurvePoint(x: 1, y: 1)]); return a }
    static let looks: [(String, Adjustments)] = [("curve", curveOnly), ("mixer", Adjustments().setting(.mixRedHue, to: 100)),
                                                 ("grading", Adjustments().setting(.gradingMidtonesSaturation, to: 100))]
    @MainActor @Test(arguments: looks) func curveMixerAndGradingLooksReachTheViewfinderTheBakeAndTheRAWEdit(name: String, look: Adjustments) async throws {   // Review Focus 3
        #expect(look.hasColourChanges); #expect(!look.isIdentity); let input = SIMD3<Float>(0.75, 0.25, 0.25), expected = ColourMath.apply(look, to: input)
        #expect(maxDiff(expected, input) > 0.05, "\(name) changes the sample"); let cube = ColourCubeCache().cube(for: look); #expect(cube == LookCompiler.cube(for: look))
        let patch = try TestFiles.patch(input); let viewfinder = try PixelReader.rgb(LookRenderer.shared.renderColourAndVignette(patch, cube: cube, vignette: 0), x: 4, y: 4)
        let editor = try PixelReader.rgb(LookRenderer.shared.render(patch, adjustments: look), x: 4, y: 4)
        #expect(maxDiff(viewfinder, expected) < 0.01); #expect(maxDiff(editor, viewfinder) < 0.002)
        let baked = try LookBaker.bake(try TestFiles.heicData(width: 64, height: 64, rgb: input), adjustments: look)
        #expect(maxDiff(try PixelReader.rgb(try #require(CIImage(data: baked)), x: 32, y: 32), expected) < 0.03)
        let dir = try TestFiles.directory(), dng = dir.appending(path: "OC_0001.DNG"); try Data("dng bytes".utf8).write(to: dng)
        let camera = CameraLook(id: UUID(), name: name, adjustments: look); _ = await LookCapture.finish(PhotoCaptureResult(saved: [dng], error: nil), look: camera, format: .raw,
                                     heicURL: dir.appending(path: "OC_0001.HEIC"), dngURL: dng, edits: EditStore(directory: dir))
        #expect(try EditStore(directory: dir).load(stem: "OC_0001").adjustments == look)
        #expect(try JSONDecoder().decode(EditFileVersion.self, from: Data(contentsOf: EditStore(directory: dir).url(forStem: "OC_0001"))).version == PhotoEdit.currentVersion)
        #expect(try JSONDecoder().decode(CameraLook.self, from: JSONEncoder().encode(camera)) == camera) } }
