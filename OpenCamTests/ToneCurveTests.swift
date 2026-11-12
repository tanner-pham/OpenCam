import Foundation
import Testing
@testable import OpenCam

@Suite struct ToneCurveTests {
    func curve(_ p: [(Double, Double)]) -> ToneCurve { ToneCurve(points: p.map { CurvePoint(x: $0.0, y: $0.1) }) }
    @Test func identityAndThroughItsPoints() {
        for i in 0...100 { let x = Float(i) / 100; #expect(abs(ToneCurve.identity.value(at: x) - x) < 1e-6) }
        let lift = curve([(0, 0), (0.5, 0.6), (1, 1)]); #expect(abs(lift.value(at: 0.5) - 0.6) < 1e-6); #expect(abs(lift.value(at: 0.25) - 0.315) < 1e-5)   // m0 1.2, m1 0.96
        let ends = curve([(0.1, 0.2), (0.9, 0.8)]); #expect(ends.value(at: 0) == 0.2); #expect(ends.value(at: 1) == 0.8); #expect(abs(ends.value(at: 0.5) - 0.5) < 1e-6)
        #expect(abs(curve([(0, 0), (0.4, 0.8), (0.6, 0.8), (1, 1)]).value(at: 0.5) - 0.8) < 1e-6)            // a plateau stays flat
    }
    @Test func curveNeverOvershootsItsPoints() {   // Review Focus 4
        var seed: UInt64 = 42
        func next() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 11) / Double(1 << 53) }
        for _ in 0..<200 {
            let c = curve([(0, next())] + (0..<Int(next() * 6)).map { _ in (0.05 + 0.9 * next(), next()) } + [(1, next())]); let p = c.points
            for k in 0..<(p.count - 1) {
                let lo = Float(min(p[k].y, p[k + 1].y)), hi = Float(max(p[k].y, p[k + 1].y))
                for s in 0...50 {
                    let y = c.value(at: Float(p[k].x + (p[k + 1].x - p[k].x) * Double(s) / 50)); #expect(y >= lo - 1e-5 && y <= hi + 1e-5, "\(p) segment \(k)") } } }
        let rising = curve([(0, 0.1), (0.2, 0.15), (0.3, 0.6), (0.7, 0.62), (1, 0.9)]); var last: Float = 0
        for i in 0...1000 { let y = rising.value(at: Float(i) / 1000); #expect(y >= last - 1e-6); last = y } }
    @Test func normalisesWhatItIsGiven() throws {
        #expect(ToneCurve.identity.points == [CurvePoint(x: 0, y: 0), CurvePoint(x: 1, y: 1)])
        #expect(curve([(1.2, 1), (0.12345, 0.5), (-0.1, 0), (0.125, 0.9)]).points == [CurvePoint(x: 0, y: 0), CurvePoint(x: 0.123, y: 0.5), CurvePoint(x: 1, y: 1)])
        #expect(curve([(0.5, 0.5)]) == .identity); let many = curve((0...19).map { (Double($0) / 19, Double($0) / 19) })
        #expect(many.points.count == 16); #expect(many.points.last == CurvePoint(x: 1, y: 1))
        let json = Data(#"{"master": {"points": [{"x": 0, "y": 0.1}, {"x": 1, "y": 1}]}, "luminance": {}}"#.utf8); let decoded = try JSONDecoder().decode(ToneCurves.self, from: json)
        #expect(decoded.master == curve([(0, 0.1), (1, 1)])); #expect(decoded.red.isIdentity); #expect(!decoded.isIdentity) }
    @Test func theMinGapIsCheckedInWholeThousandthsAndTheEndsStay() {
        #expect(curve([(0, 0), (0.2, 0.3), (0.21, 0.4), (1, 1)]).points.count == 4)           // 0.21 - 0.20 is a gap of 10: kept
        #expect(curve([(0, 0), (0.2, 0.3), (0.209, 0.4), (1, 1)]).points.count == 3)          // gap 9: the later one is dropped
        #expect(curve([(0, 0), (0.995, 0.5), (1, 1)]).points == [CurvePoint(x: 0, y: 0), CurvePoint(x: 1, y: 1)])   // inner point near the last goes, the last stays
        #expect(curve([(0.5, 0.2), (0.505, 0.8)]) == .identity)                                // ends too close
    }
    @Test func aCoordinateThatIsNotFiniteBecomesZero() throws {
        let nanX = curve([(.nan, 0.5), (0, 0), (1, 1)]); #expect(nanX.points.allSatisfy { $0.x.isFinite && $0.y.isFinite }); #expect(nanX.points.count == 2)
        #expect(curve([(0, 0), (0.5, .nan), (1, 1)]).points[1] == CurvePoint(x: 0.5, y: 0))
        #expect(curve([(0, 0), (0.5, .infinity), (-.infinity, 0.3), (1, 1)]).points.allSatisfy { $0.x.isFinite && $0.y.isFinite })
        let json = Data(#"{"points": [{"x": 0, "y": 0}, {"x": 1, "y": 1}]}"#.utf8); #expect(try JSONDecoder().decode(ToneCurve.self, from: json).isIdentity)
        #expect(!curve([(0, 0), (0.5, 0.5), (1, 1)]).isIdentity); #expect(curve([(0, 0), (1, 1)]).isIdentity); #expect(curve([(0.5, 0.5)]).isIdentity)
        let encoded = String(decoding: try JSONEncoder().encode(ToneCurve.identity), as: UTF8.self); #expect(!encoded.contains("isIdentity"))
    }
}
