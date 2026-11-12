import CoreGraphics
import Testing
@testable import OpenCam

struct MaskGeometryTests {
    private let size = CGSize(width: 200, height: 100)

    @Test func pointAndLocationAreInverse() {
        let point = MaskPoint(x: 0.25, y: 0.8)
        let back = MaskGeometry.point(MaskGeometry.location(point, in: size), in: size)
        #expect(abs(back.x - point.x) < 1e-9)
        #expect(abs(back.y - point.y) < 1e-9)
        #expect(MaskGeometry.location(point, in: size) == CGPoint(x: 50, y: 80))
    }

    @Test func pointsOutsideThePictureAreClamped() {
        let point = MaskGeometry.point(CGPoint(x: -30, y: 400), in: size)
        #expect(point == MaskPoint(x: 0, y: 1))
        #expect(MaskGeometry.point(CGPoint(x: 300, y: -5), in: size) == MaskPoint(x: 1, y: 0))
    }

    @Test func radiusDragKeepsTheGrabOffset() {
        let centre = MaskPoint(x: 0.5, y: 0.5)
        // 120 pt on a 100 pt short side: the handle is held on the right edge, 100 pt from the centre.
        let touch = MaskGeometry.point(CGPoint(x: 220, y: 50), in: size)
        let grab = MaskGeometry.radiusGrabOffset(trueRadius: 1.2, centre: centre, touch: touch, in: size)
        #expect(abs(grab - 0.2) < 1e-9)
        #expect(abs(MaskGeometry.radius(dragging: touch, from: centre, grabOffset: grab, in: size) - 1.2) < 1e-9)
        let inside = MaskGeometry.point(CGPoint(x: 190, y: 50), in: size)
        #expect(abs(MaskGeometry.radius(dragging: inside, from: centre, grabOffset: grab, in: size) - 1.1) < 1e-9)
    }

    @Test func radiusIsMeasuredAgainstTheShorterSide() {
        let centre = MaskPoint(x: 0.5, y: 0.5)
        let edge = MaskGeometry.point(CGPoint(x: 150, y: 50), in: size)
        #expect(abs(MaskGeometry.radius(from: centre, to: edge, in: size) - 0.5) < 1e-9)
    }
}
