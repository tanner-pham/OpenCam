import Foundation
import Testing
@testable import OpenCam

/// Prints how long a colour table takes to build with curves, since a curve drag rebuilds it for every preview. Debug
/// Simulator numbers, relative only; the bound is generous on purpose: this reports, it does not race.
@Suite(.serialized) struct CurveTableTimingTests {
    private static let bound = Duration.seconds(5)

    @Test func tableBuildTimes() {
        let sixteen = ToneCurve(points: (0..<16).map { CurvePoint(x: Double($0) / 15, y: pow(Double($0) / 15, 0.8)) })
        var full = Adjustments(); full.curves.master = sixteen; full.curves.red = sixteen; full.curves.green = sixteen; full.curves.blue = sixteen
        #expect(sixteen.points.count == 16)
        #expect(PerfClock.report("cube: Adjustments()", runs: 5) { _ = LookCompiler.cube(for: Adjustments()) } < Self.bound)
        #expect(PerfClock.report("cube: colour study", runs: 5) { _ = LookCompiler.cube(for: LookSeeder.colourStudy) } < Self.bound)
        #expect(PerfClock.report("cube: four 16-point curves", runs: 5) { _ = LookCompiler.cube(for: full) } < Self.bound)
    }
}
