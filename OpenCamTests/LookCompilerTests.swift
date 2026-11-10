import Foundation
import Testing
@testable import OpenCam

@Suite struct LookCompilerTests {
    func index(_ r: Int, _ g: Int, _ b: Int) -> Int { ((b * 33 + g) * 33 + r) * 4 }
    @Test func identityCubeEqualsTheLattice() {
        let cube = LookCompiler.cube(for: Adjustments()), lattice = LookCompiler.lattice(dimension: 33)
        #expect(cube.dimension == 33); #expect(cube.data.count == 33 * 33 * 33 * 4); #expect(cube.cubeData.count == 33 * 33 * 33 * 4 * 4)
        #expect(zip(cube.data, lattice.data).allSatisfy { abs($0 - $1) < 1e-5 })
    }
    @Test func latticeOrderIsRedThenGreenThenBlue() {
        let l = LookCompiler.lattice(dimension: 33).data
        #expect(l[index(1, 0, 0)] == Float(1) / 32); #expect(l[index(1, 0, 0) + 1] == 0)
        #expect(l[index(0, 1, 0) + 1] == Float(1) / 32); #expect(l[index(0, 0, 1) + 2] == Float(1) / 32); #expect(l[index(32, 32, 32) + 3] == 1)
    }
    @Test func plusOneStopSpotValues() {
        let a = Adjustments().setting(.exposure, to: 1), d = LookCompiler.cube(for: a).data, mid = index(16, 16, 16)
        for c in 0..<3 { #expect(abs(d[mid + c] - 0.68584) < 1e-4) }
        #expect(d[mid + 3] == 1)
        #expect(abs(d[index(8, 20, 30) + 1] - ColourMath.apply(a, to: SIMD3(8, 20, 30) / 32).y) < 1e-6)
    }
}
