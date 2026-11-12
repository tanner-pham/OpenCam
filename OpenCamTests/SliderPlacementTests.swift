import SwiftUI
import Testing
@testable import OpenCam

/// Where the open control's slider lives: in the strip on the folded display, in the picture elsewhere.
@Suite struct SliderPlacementTests {
    @Test func theFoldedDisplayUsesTheStrip() {
        #expect(SliderPlacement.resolve(isFoldedDisplay: true, stripEdge: .trailing) == .strip)
        #expect(SliderPlacement.resolve(isFoldedDisplay: true, stripEdge: .leading) == .strip)
    }

    @Test func theOpenDisplayUsesThePictureBesideTheStripOrTheTrailingEdge() {
        #expect(SliderPlacement.resolve(isFoldedDisplay: false, stripEdge: .leading) == .picture(edge: .leading))
        #expect(SliderPlacement.resolve(isFoldedDisplay: false, stripEdge: .trailing) == .picture(edge: .trailing))
        #expect(SliderPlacement.resolve(isFoldedDisplay: false, stripEdge: nil) == .picture(edge: .trailing))
        // No strip to swap, even on the folded display.
        #expect(SliderPlacement.resolve(isFoldedDisplay: true, stripEdge: nil) == .picture(edge: .trailing))
    }

    @Test func aForcedPlacementUsesThePictureOnTheFoldedDisplay() {
        #expect(SliderPlacement.resolve(isFoldedDisplay: true, stripEdge: .trailing, isForcedIntoPicture: true) == .picture(edge: .trailing))
        #expect(SliderPlacement.resolve(isFoldedDisplay: true, stripEdge: .leading, isForcedIntoPicture: true) == .picture(edge: .leading))
        #expect(SliderPlacement.resolve(isFoldedDisplay: true, stripEdge: .trailing, isForcedIntoPicture: false) == .strip)
    }
}
