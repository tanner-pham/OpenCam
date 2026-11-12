import Testing
@testable import OpenCam

struct BrushStrokeBuilderTests {
    @Test func pressureScalesTheDab() {
        for (pressure, expected) in [(0.0, 0.035), (1.0, 0.1), (nil, 0.1), (2.0, 0.1), (-1.0, 0.035)] as [(Double?, Double)] {
            var builder = BrushStrokeBuilder(radius: 0.1, isErasing: false)
            let isAdded = builder.add(MaskPoint(x: 0.5, y: 0.5), pressure: pressure)
            #expect(isAdded)
            #expect(abs((builder.stroke.dabs.first?.radius ?? 0) - expected) < 1e-9, "\(String(describing: pressure))")
        }
    }

    @Test func closePointsAreSkipped() {
        var builder = BrushStrokeBuilder(radius: 0.1, isErasing: false)
        let first = builder.add(MaskPoint(x: 0.5, y: 0.5), pressure: nil)
        let close = builder.add(MaskPoint(x: 0.51, y: 0.5), pressure: nil)   // 0.01 < a quarter of 0.1
        let far = builder.add(MaskPoint(x: 0.53, y: 0.5), pressure: nil)
        #expect(first); #expect(!close); #expect(far)
        #expect(builder.stroke.dabs.count == 2)
    }

    @Test func erasingStrokesAreMarked() {
        var builder = BrushStrokeBuilder(radius: 0.05, isErasing: true)
        _ = builder.add(MaskPoint(x: 0.2, y: 0.2), pressure: nil)
        #expect(builder.stroke.isErasing)
        #expect(!BrushStrokeBuilder(radius: 0.05, isErasing: false).stroke.isErasing)
    }
}
