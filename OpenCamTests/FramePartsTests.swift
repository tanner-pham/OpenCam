import CoreGraphics
import CoreImage
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
    @Test func thePipelineTurnsTheImageThenMirrorsItForAFrontCamera() {
        #expect(FrameOrientation.plan(angle: 90, isFront: false) == FrameOrientation(imageRotation: .right, imageMirrors: false))
        #expect(FrameOrientation.plan(angle: 90, isFront: true) == FrameOrientation(imageRotation: .right, imageMirrors: true))
        #expect(FrameOrientation.plan(angle: 180, isFront: false).imageRotation == .down)
        #expect(FrameOrientation.plan(angle: 270, isFront: true) == FrameOrientation(imageRotation: .left, imageMirrors: true))
        #expect(FrameOrientation.plan(angle: 0, isFront: false) == FrameOrientation(imageRotation: .up, imageMirrors: false))
    }
    /// A 2 x 1 picture, red on the left and blue on the right, through the transform the frame callback uses.
    @Test func theTransformMirrorsAndTurnsRealPixels() throws {
        let red = CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1))
        let blue = CIImage(color: CIColor(red: 0, green: 0, blue: 1)).cropped(to: CGRect(x: 0, y: 0, width: 2, height: 1))
        let picture = red.composited(over: blue)

        let mirrored = FrameOrientation.plan(angle: 0, isFront: true).apply(to: picture)
        #expect(mirrored.extent.size == CGSize(width: 2, height: 1))
        let left = try PixelReader.rgb(mirrored, x: Int(mirrored.extent.minX), y: Int(mirrored.extent.minY))
        let right = try PixelReader.rgb(mirrored, x: Int(mirrored.extent.minX) + 1, y: Int(mirrored.extent.minY))
        #expect(right.x > 0.5); #expect(right.z < 0.5)   // red is now on the right
        #expect(left.z > 0.5); #expect(left.x < 0.5)

        let turned = FrameOrientation.plan(angle: 90, isFront: false).apply(to: picture)
        #expect(turned.extent.size == CGSize(width: 1, height: 2))
    }
    /// A view swapped out by a layout change is taken down after its replacement set the look; its clear changes nothing.
    @Test func onlyTheViewThatLastSetTheLookCanClearIt() {
        let frames = FramePipeline()
        let a = UUID(), b = UUID()
        let warm = Adjustments().setting(.temperature, to: 20), cool = Adjustments().setting(.temperature, to: -20)
        let picture = CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: CGRect(x: 0, y: 0, width: 2, height: 1))
        frames.setLook(warm, owner: a)
        frames.setLook(cool, owner: b)
        frames.changeLook(warm, owner: a)
        #expect(frames.look == cool)
        frames.receive(picture)
        frames.clearLook(owner: a)
        #expect(frames.look == cool)
        frames.receive(picture)
        frames.clearLook(owner: b)
        #expect(frames.look == nil); #expect(frames.takeLatest() == nil)
        frames.receive(picture)
        #expect(frames.takeLatest() == nil)
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
