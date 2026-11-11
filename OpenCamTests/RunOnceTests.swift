import Testing
@testable import OpenCam

/// The Library's deferred first load has three triggers (camera started, Library about to show, one second after launch);
/// it must run on the first and never again.
@Suite struct RunOnceTests {
    @Test func runsOnTheFirstTriggerOnly() {
        var once = RunOnce()
        var count = 0
        #expect(!once.hasRun)
        once.run { count += 1 }       // the Library is about to show
        once.run { count += 1 }       // the camera started
        once.run { count += 1 }       // a second has passed
        #expect(count == 1); #expect(once.hasRun)
    }

    @Test func eachTriggerOrderLoadsOnce() {
        for first in 0..<3 {
            var once = RunOnce()
            var loads: [Int] = []
            for trigger in [first] + (0..<3).filter({ $0 != first }) {
                once.run { loads.append(trigger) }
            }
            #expect(loads == [first])
        }
    }
}
