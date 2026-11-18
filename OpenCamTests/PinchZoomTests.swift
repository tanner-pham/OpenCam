import Testing
@testable import OpenCam

@Suite struct PinchZoomTests {
    static let ultra = Lens(id: "ultra", kind: .ultraWide, deviceUniqueID: "ultra", zoomFactor: 1, label: "0.5x")
    static let wide = Lens(id: "wide", kind: .wide, deviceUniqueID: "wide", zoomFactor: 1, label: "1x")
    static let wideCrop = Lens(id: "wide@2", kind: .wide, deviceUniqueID: "wide", zoomFactor: 2, label: "2x")
    static let front = Lens(id: "outer", kind: .outerUltraWide, deviceUniqueID: "outer", zoomFactor: 1, label: "Front")
    static let hevc = VideoCodec(family: .hevc, quality: "High", codecType: "hvc1", bitrateTier: .high)

    @Test func withNoPinchTheTargetIsTheConfigurationsZoom() {
        for base in [1.0, 2.0, 4.0] {
            #expect(PinchZoom.target(base: base, pinch: 1, formatMax: 129) == base)
        }
    }

    @Test func magnificationScalesFromTheStartFactor() {
        #expect(PinchZoom.factor(from: 2, magnification: 1.5) == 3)
    }

    @Test func clampsBetweenOneAndTheCap() {
        #expect(PinchZoom.factor(from: 1, magnification: 0.1) == 1)
        #expect(PinchZoom.factor(from: 1, magnification: 100) == 10)
        #expect(PinchZoom.factor(from: 2, magnification: .nan) == 2)
        #expect(PinchZoom.factor(from: 2, magnification: 0) == 2)
        #expect(PinchZoom.factor(from: 2, magnification: -1) == 2)
        #expect(PinchZoom.factor(from: 2, magnification: .infinity) == 2)
    }

    @Test func targetStaysUnderTheFormat() {
        #expect(PinchZoom.target(base: 2, pinch: 3, formatMax: 5) == 5)
        #expect(PinchZoom.target(base: 4, pinch: 3, formatMax: 3) == 4)
    }

    @Test func labelReadsTheLiveFactor() {
        #expect(PinchZoom.label(for: Self.wide, pinch: 1.6) == "1.6x")
        #expect(PinchZoom.label(for: Self.wide, pinch: 10) == "10x")
        #expect(PinchZoom.label(for: Self.ultra, pinch: 2) == "1x")
        #expect(PinchZoom.label(for: Self.wideCrop, pinch: 1.5) == "3x")
        #expect(PinchZoom.label(for: Self.front, pinch: 2) == "2x")
        #expect(PinchZoom.label(for: Self.wide, pinch: 1) == nil)
        #expect(PinchZoom.label(for: Self.wide, pinch: 1.04) == nil)
    }

    @Test func keepsAcrossALookChangeButNotLensModeOrFormat() {
        let video = VideoOption(lensID: "wide", codec: Self.hevc, resolution: .named(width: 3840, height: 2160), frameRate: 30, colour: .rec709)
        let otherVideo = VideoOption(lensID: "wide", codec: Self.hevc, resolution: .named(width: 3840, height: 2160), frameRate: 60, colour: .rec709)
        let photo = PhotoOption(lensID: "wide", format: .heif, width: 4000, height: 3000)
        let otherPhoto = PhotoOption(lensID: "wide", format: .raw, width: 4000, height: 3000)
        let base = SessionConfiguration(lens: Self.wide, mode: .photo, video: video, photo: photo, includesAudio: false)
        #expect(PinchZoom.keeps(from: base, to: base))

        var look = base; look.needsFrames = true
        #expect(PinchZoom.keeps(from: base, to: look))
        var sound = base; sound.includesAudio = true
        #expect(PinchZoom.keeps(from: base, to: sound))
        var recorder = base; recorder.recorder = .writer
        #expect(PinchZoom.keeps(from: base, to: recorder))
        var combined = base; combined.combined = CombinedLens(deviceUniqueID: "dual", zoomFactor: 2)
        #expect(PinchZoom.keeps(from: base, to: combined))

        var lens = base; lens.lens = Self.ultra
        #expect(!PinchZoom.keeps(from: base, to: lens))
        var mode = base; mode.mode = .video
        #expect(!PinchZoom.keeps(from: base, to: mode))
        var videoChange = base; videoChange.video = otherVideo
        #expect(!PinchZoom.keeps(from: base, to: videoChange))
        var photoChange = base; photoChange.photo = otherPhoto
        #expect(!PinchZoom.keeps(from: base, to: photoChange))
        #expect(!PinchZoom.keeps(from: nil, to: base))
    }
}
