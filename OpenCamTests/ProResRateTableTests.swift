import Testing
@testable import OpenCam

@Suite struct ProResRateTableTests {
    func rate(_ quality: String, _ width: Int, _ height: Int, _ fps: Int) -> Double? {
        ProResRateTable.megabitsPerSecond(quality: quality, width: width, height: height, frameRate: fps)
    }

    @Test func publishedCellsAreApples() {
        #expect(rate("422 HQ", 1920, 1080, 30) == 220)
        #expect(rate("422 HQ", 3840, 2160, 30) == 884)
        #expect(rate("422 HQ", 3840, 2160, 24) == 707)
        #expect(rate("422", 3840, 2160, 60) == 1178)
        #expect(rate("422 Proxy", 1920, 1080, 24) == 36)
        #expect(rate("422 LT", 1280, 720, 50) == 84)
        #expect(rate("422 HQ", 2160, 3840, 30) == 884)
    }

    @Test func aKindSizeOrRateWithNoRowHasNoCell() {
        #expect(rate("422 HQ", 1920, 1440, 30) == nil)
        #expect(rate("4444", 1920, 1080, 30) == nil)
        #expect(rate("422 HQ", 3840, 2160, 48) == nil)
    }
}
