import Testing
@testable import OpenCam

@Suite struct TimingJournalTests {
    @Test func describesALensChangeOnTheCombinedCamera() {
        let ultra = Lens(id: "ultraWide", kind: .ultraWide, deviceUniqueID: "fixture-ultraWide", zoomFactor: 1, label: "0.5x")
        let wide = Lens(id: "wide", kind: .wide, deviceUniqueID: "fixture-wide", zoomFactor: 2, label: "1x")
        let before = SessionConfiguration(lens: ultra, mode: .video, video: nil, photo: nil, includesAudio: false, needsFrames: false,
                                          recorder: .system, combined: CombinedLens(deviceUniqueID: "fixture-dual", zoomFactor: 1))
        let after = SessionConfiguration(lens: wide, mode: .video, video: nil, photo: nil, includesAudio: false, needsFrames: false,
                                         recorder: .system, combined: CombinedLens(deviceUniqueID: "fixture-dual", zoomFactor: 2))
        #expect(TimingJournal.describeLensChange(to: after, from: before) == "lens \(ultra.label) to \(wide.label) on the combined camera")
    }
}
