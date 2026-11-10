import Testing
@testable import OpenCam

@Suite struct RenderCoalescerTests {
    @Test func firstRequestStartsAtOnce() {
        var queue = RenderCoalescer<Int>()
        #expect(queue.isIdle)
        #expect(queue.request(1)?.value == 1); #expect(!queue.isIdle)
        #expect(queue.finish() == nil); #expect(queue.isIdle)
    }
    @Test func aBurstWhileRunningRendersOnlyTheLatestOnce() {
        var queue = RenderCoalescer<Int>()
        #expect(queue.request(1)?.value == 1)
        for value in 2...30 { #expect(queue.request(value) == nil) }   // nothing else starts while one runs
        #expect(queue.finish()?.value == 30)                           // the latest pending value, once
        #expect(queue.finish() == nil); #expect(queue.isIdle)
    }
    @Test func eachStartedRenderHasAHigherGeneration() {
        var queue = RenderCoalescer<Int>()
        let first = queue.request(1)
        _ = queue.request(2)
        let second = queue.finish()
        #expect(queue.finish() == nil)
        let third = queue.request(3)
        let generations = [first, second, third].compactMap { $0?.generation }
        #expect(generations.count == 3); #expect(generations == generations.sorted()); #expect(Set(generations).count == 3)
    }
}
