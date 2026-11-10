import Foundation
import Testing
@testable import OpenCam

@Suite struct CaptureAccessTests {
    @Test func microphoneDeniedStillRecordsVideoWithoutSound() throws {
        let access = CaptureAccess(camera: .authorized, microphone: .denied)
        #expect(access.canUseCamera); #expect(!access.recordsSound)
        let caps = try Fixture.load(), lens = try #require(caps.lenses.first { $0.id == "wide" })
        let resolver = RecordSelectionResolver(options: caps.videoOptions, lens: lens)
        let video = try #require(resolver.defaultSelection().flatMap(resolver.option(for:)))
        let config = SessionConfiguration.make(lens: lens, mode: .video, video: video, photo: nil, access: access)
        #expect(!config.includesAudio); #expect(config.video == video)
    }
}
