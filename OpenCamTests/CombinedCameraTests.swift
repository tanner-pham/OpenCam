import Testing
@testable import OpenCam

/// The combined back camera's answer for each lens: the zoom to use on it, or nil when it cannot record that option.
@Suite struct CombinedCameraTests {
    static let camera = CombinedCamera(deviceUniqueID: "dual", baseZoomByDeviceID: ["ultra": 1, "wide": 2], formats: [
        CombinedFormat(width: 3840, height: 2160, colourSpaces: [0, 1], frameRateRanges: [1...60], maxZoomFactor: 129.125),
        CombinedFormat(width: 3840, height: 2160, colourSpaces: [2], frameRateRanges: [1...60], maxZoomFactor: 129.125),
        CombinedFormat(width: 1920, height: 1080, colourSpaces: [0], frameRateRanges: [1...29.97], maxZoomFactor: 3),
    ])

    static let ultra = Lens(id: "ultra", kind: .ultraWide, deviceUniqueID: "ultra", zoomFactor: 1, label: "0.5x")
    static let wide = Lens(id: "wide", kind: .wide, deviceUniqueID: "wide", zoomFactor: 1, label: "1x")
    static let wideCrop = Lens(id: "wide@2", kind: .wide, deviceUniqueID: "wide", zoomFactor: 2, label: "2x")
    static let outer = Lens(id: "outer", kind: .outerUltraWide, deviceUniqueID: "outer", zoomFactor: 1, label: "Front")

    func option(_ lens: Lens, width: Int, height: Int, rate: Int, colour: ColourMode) -> VideoOption {
        VideoOption(lensID: lens.id, codec: VideoCodec(family: .hevc, quality: "High", codecType: "hvc1", bitrateTier: .high),
                    resolution: .named(width: width, height: height), frameRate: rate, colour: colour)
    }

    func served(_ lens: Lens, width: Int = 3840, height: Int = 2160, rate: Int = 30, colour: ColourMode = .rec709,
                mode: CaptureMode = .video) -> CombinedLens? {
        Self.camera.lens(for: lens, mode: mode, video: option(lens, width: width, height: height, rate: rate, colour: colour))
    }

    @Test func eachBackLensGetsItsZoom() {
        #expect(served(Self.ultra) == CombinedLens(deviceUniqueID: "dual", zoomFactor: 1))
        #expect(served(Self.wide) == CombinedLens(deviceUniqueID: "dual", zoomFactor: 2))
        #expect(served(Self.wideCrop) == CombinedLens(deviceUniqueID: "dual", zoomFactor: 4))
    }

    @Test func hlgAndLogUseTheHLGFormat() {
        #expect(served(Self.wide, rate: 60, colour: .hlg) != nil)
        #expect(served(Self.wide, rate: 60, colour: .log) != nil)
        #expect(served(Self.wide, rate: 60, colour: .appleLog) == nil)
    }

    @Test func aRateAboveTheFormatsIsNotServed() {
        #expect(served(Self.wide, rate: 120) == nil)
        #expect(served(Self.wide, width: 1920, height: 1080, rate: 30) != nil)
        #expect(served(Self.wide, width: 1920, height: 1080, rate: 60) == nil)
    }

    @Test func aLensItDoesNotHoldIsNotServed() {
        #expect(served(Self.outer) == nil)
    }

    @Test func photoModeAndNoOptionAreNotServed() {
        #expect(served(Self.wide, mode: .photo) == nil)
        #expect(Self.camera.lens(for: Self.wide, mode: .video, video: nil) == nil)
    }

    @Test func aZoomPastTheFormatIsNotServed() {
        #expect(served(Self.wideCrop, width: 1920, height: 1080, rate: 30) == nil)
    }
}
