import Foundation
import Testing
@testable import OpenCam

@Suite struct LaunchTimelineTests {
    private static let processStart = Date(timeIntervalSinceReferenceDate: 100)

    @Test func marksAndNotesKeepTheirOrderInOneLine() {
        var timeline = LaunchTimeline(processStart: Self.processStart)
        timeline.mark("model", at: Self.processStart.addingTimeInterval(0.082))
        timeline.mark("start", at: Self.processStart.addingTimeInterval(0.240))
        timeline.note("audio yes")
        #expect(timeline.line == "[timing] launch model 82 ms, start 240 ms, audio yes")
    }

    @Test func aMarkRoundsToTheNearestMillisecond() {
        var timeline = LaunchTimeline(processStart: Self.processStart)
        timeline.mark("model", at: Self.processStart.addingTimeInterval(0.0006))
        #expect(timeline.line == "[timing] launch model 1 ms")
    }
}
