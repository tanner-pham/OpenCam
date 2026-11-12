import CoreGraphics
import Foundation
import Testing
@testable import OpenCam

@MainActor @Suite struct CurveEditingTests {
    let s = ToneCurve(points: [CurvePoint(x: 0, y: 0), CurvePoint(x: 0.5, y: 0.6), CurvePoint(x: 1, y: 1)])
    @Test func hitsPointsThenTheCurve() {
        #expect(s.hit(CurvePoint(x: 0.52, y: 0.61), radius: 0.05) == .point(1)); #expect(s.hit(CurvePoint(x: 0.25, y: 0.33), radius: 0.05) == .curve)     // value 0.315
        #expect(s.hit(CurvePoint(x: 0.25, y: 0.6), radius: 0.05) == .none); #expect(s.hit(CurvePoint(x: 0.99, y: 0.99), radius: 0.05) == .point(2)) }
    @Test func aTapOnTheCurveAddsAPointWithoutChangingThePicture() throws {
        let drag = try #require(CurveDrag.begin(on: s, at: CurvePoint(x: 0.25, y: 0.32), radius: 0.05)); let added = drag.curve(translation: CurvePoint(x: 0, y: 0), margin: 0.1)
        #expect(added.points.count == 4); #expect(added.points[1] == CurvePoint(x: 0.25, y: 0.315))
        for i in 0...20 { let x = Float(i) / 20; #expect(abs(added.value(at: x) - s.value(at: x)) < 0.01) }   // new tangents: within 0.01
        #expect(CurveDrag.begin(on: s, at: CurvePoint(x: 0.25, y: 0.9), radius: 0.05) == nil) }
    @Test func dragsNeverCrossANeighbourAndTheEndsStay() throws {   // Review Focus 4
        let drag = try #require(CurveDrag.begin(on: s, at: CurvePoint(x: 0.5, y: 0.6), radius: 0.05))
        #expect(drag.curve(translation: CurvePoint(x: 0.58, y: 0.2), margin: 0.1).points[1] == CurvePoint(x: 0.99, y: 0.8))
        #expect(drag.curve(translation: CurvePoint(x: -0.55, y: 0), margin: 0.1).points[1] == CurvePoint(x: 0.01, y: 0.6))
        #expect(drag.curve(translation: CurvePoint(x: 0.7, y: 0), margin: 0.1).points.count == 2)          // past the side margin: removed
        #expect(drag.curve(translation: CurvePoint(x: 0, y: -0.75), margin: 0.1).points.count == 2)        // off the bottom: removed
        #expect(drag.curve(translation: CurvePoint(x: 0, y: -0.65), margin: 0.1).points[1].y == 0)         // inside the margin: clamped
        let end = try #require(CurveDrag.begin(on: s, at: CurvePoint(x: 0, y: 0), radius: 0.05)); let lifted = end.curve(translation: CurvePoint(x: -0.5, y: -0.5), margin: 0.1)
        #expect(lifted.points.count == 3); #expect(lifted.points[0] == CurvePoint(x: 0, y: 0))
        #expect(end.curve(translation: CurvePoint(x: 0.7, y: 0.1), margin: 0.1).points[0] == CurvePoint(x: 0.49, y: 0.1))
        #expect(s.removing(0) == s); #expect(s.removing(2) == s); #expect(s.removing(1) == .identity)
        #expect(try #require(CurveDrag.begin(on: s, at: CurvePoint(x: 0.52, y: 0.61), radius: 0.05)).curve(translation: CurvePoint(x: 0, y: 0), margin: 0.1) == s)   // an off-centre touch never jumps the point
        // Exactly a neighbour's x + 0.01 is kept: the gap is compared in whole thousandths, not as a Double difference.
        let four = ToneCurve(points: [CurvePoint(x: 0, y: 0), CurvePoint(x: 0.2, y: 0.3), CurvePoint(x: 0.6, y: 0.7), CurvePoint(x: 1, y: 1)])
        let inner = try #require(CurveDrag.begin(on: four, at: CurvePoint(x: 0.6, y: 0.7), radius: 0.05)); let close = inner.curve(translation: CurvePoint(x: -0.39, y: 0), margin: 0.1)
        #expect(close.points.count == 4); #expect(close.points[2] == CurvePoint(x: 0.21, y: 0.7))
        #expect(inner.curve(translation: CurvePoint(x: -0.5, y: 0), margin: 0.1).points[2] == CurvePoint(x: 0.21, y: 0.7))
        #expect(drag.curve(translation: CurvePoint(x: -0.49, y: 0), margin: 0.1).points == [CurvePoint(x: 0, y: 0), CurvePoint(x: 0.01, y: 0.6), CurvePoint(x: 1, y: 1)]) }
    @Test func geometryAndSizes() {
        let g = CurveGeometry(side: 236); #expect(g.viewPoint(CurvePoint(x: 0, y: 0)) == CGPoint(x: 12, y: 224)); #expect(g.viewPoint(CurvePoint(x: 1, y: 1)) == CGPoint(x: 224, y: 12))
        #expect(abs(g.hitRadius - 22.0 / 212) < 1e-9)
        #expect(EditorLayout.minPanelHeight(for: .curve) == 340); #expect(EditorLayout.minPanelHeight(for: .grading) == 340); #expect(EditorLayout.minPanelHeight(for: .masks) == 340); #expect(EditorLayout.minPanelHeight(for: .light) == 240) }
    @Test func curveDragRendersTheProxyOnlyThroughTheCoalescer() async throws {   // Review Focus 5
        let (model, _, _) = try await EditorFixture.make(width: 4096, height: 3072); let before = model.previewRenderCount
        let drag = try #require(CurveDrag.begin(on: model.adjustments.curves.master, at: CurvePoint(x: 0.5, y: 0.5), radius: 0.05))
        for step in 1...30 { model.adjustments.curves.master = drag.curve(translation: CurvePoint(x: 0, y: Double(step) / 100), margin: 0.1) }
        await model.waitForPreview(); #expect(model.previewRenderCount - before <= 2); #expect(model.renderedAdjustments == model.adjustments)
        #expect(model.lastRenderPixelSize == CGSize(width: 2048, height: 1536)) }
    @Test func resetCurveAndLaunchLook() async throws {
        let (model, _, looks) = try await EditorFixture.make(width: 64, height: 48)
        model.adjustments.curves.red = s; model.resetCurve(.red); #expect(model.adjustments.curves.red.isIdentity)
        _ = try LookSeeder.seedColourStudy(into: looks); #expect(try LookSeeder.seedColourStudy(into: looks) == nil)
        #expect(LookSeeder.colourStudy.curves.master.points.count == 4); #expect(LookSeeder.colourStudy.hasColourChanges); let captures = try TestFiles.directory()
        _ = try TestFiles.writeJPEG(width: 64, height: 48, rgb: SIMD3(0.5, 0.5, 0.5), to: captures.appending(path: "OC_0001.JPG"))
        let item = try #require(LibraryScanner.items(in: captures).first)
        let launched = EditorModel(item: item, edits: EditStore(directory: captures), looks: looks, launchLook: "Colour study"); await launched.load()
        #expect(launched.adjustments == LookSeeder.colourStudy); #expect(launched.lookName == "Colour study"); #expect(launched.hasUnsavedChanges) } }
