import CoreGraphics
import Foundation
import Testing
@testable import OpenCam

@Suite struct FramePartsTests {
    @Test func slotKeepsOnlyTheNewestFrame() {
        var slot = FrameSlot<Int>()
        #expect(slot.take() == nil)
        slot.put(1); slot.put(2); slot.put(3)
        #expect(slot.take() == 3); #expect(slot.take() == nil); #expect(slot.dropped == 2)
        slot.put(4); #expect(slot.take() == 4); #expect(slot.dropped == 2)
    }
    @Test func theImageIsAlwaysTurnedByThePipelineAndMirroredOnTheConnectionWhenItCan() {
        #expect(FrameOrientation.plan(angle: 90, isFront: false, connectionCanMirror: true)
                == FrameOrientation(connectionMirrors: false, imageRotation: .right, imageMirrors: false))
        #expect(FrameOrientation.plan(angle: 90, isFront: true, connectionCanMirror: true)
                == FrameOrientation(connectionMirrors: true, imageRotation: .right, imageMirrors: false))
        #expect(FrameOrientation.plan(angle: 90, isFront: true, connectionCanMirror: false)
                == FrameOrientation(connectionMirrors: false, imageRotation: .right, imageMirrors: true))
        #expect(FrameOrientation.plan(angle: 180, isFront: false, connectionCanMirror: false).imageRotation == .down)
        #expect(FrameOrientation.plan(angle: 270, isFront: false, connectionCanMirror: false).imageRotation == .left)
        #expect(FrameOrientation.plan(angle: 0, isFront: false, connectionCanMirror: false).imageRotation == .up)
    }
    @Test func watchStallsOnlyAfterTwoSecondsWithoutAFrame() {
        #expect(!FrameWatch.isStalled(framesSinceConfigure: 0, elapsed: .milliseconds(1900)))
        #expect(FrameWatch.isStalled(framesSinceConfigure: 0, elapsed: .seconds(2)))
        #expect(!FrameWatch.isStalled(framesSinceConfigure: 1, elapsed: .seconds(5)))
    }
    @Test func aspectFitCentresTheFrame() {
        let fitted = CGRect(x: 0, y: 0, width: 1920, height: 1080).applying(FrameFit.aspectFit(CGRect(x: 0, y: 0, width: 1920, height: 1080), in: CGSize(width: 1000, height: 1000)))
        #expect(abs(fitted.minX) < 0.001); #expect(abs(fitted.width - 1000) < 0.001)
        #expect(abs(fitted.minY - 218.75) < 0.001); #expect(abs(fitted.height - 562.5) < 0.001)
    }
}
