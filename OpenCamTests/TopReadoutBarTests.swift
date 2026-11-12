import Testing
@testable import OpenCam

/// Which readouts the top bar shows: video keeps FPS and timecode, photo shows the same five as the vertical photo row.
@Suite struct TopReadoutBarTests {
    @Test func videoKeepsFPSTimecodeAndTheWhiteBalanceTint() {
        #expect(TopReadoutBar.readouts(for: .video) == [.frameRate, .control(.shutter), .timecode, .control(.iso), .control(.temperature), .control(.tint)])
    }

    @Test func photoShowsShutterISOEVWhiteBalanceAndFocusWithoutFPSOrTimecode() {
        let photo = TopReadoutBar.readouts(for: .photo)
        #expect(photo == [.control(.shutter), .control(.iso), .control(.bias), .control(.temperature), .control(.focus)])
        #expect(!photo.contains(.frameRate)); #expect(!photo.contains(.timecode))
    }

    /// The horizontal photo bar and the vertical photo row are one set, in one order.
    @Test func photoIsTheSameSetInBothOrientations() {
        #expect(TopReadoutBar.readouts(for: .photo) == PhotoReadoutRow.controls.map { TopReadoutBar.Readout.control($0) })
    }
}
