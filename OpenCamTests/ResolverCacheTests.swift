import Foundation
import Testing
@testable import OpenCam

/// The model keeps one record resolver per lens; new capabilities must drop them, so answers follow the new list.
@MainActor @Suite struct ResolverCacheTests {
    @Test func replacingTheCapabilitiesDropsTheCachedResolvers() throws {
        let capabilities = try Fixture.loadDuo()
        let model = CameraModel(config: LaunchConfig(), capabilities: capabilities, isSimulator: true, defaults: try Fixture.freshDefaults())
        let lens = model.lensID
        // Warm the cache for the lens.
        #expect(model.recordResolver.chips(.codec, for: model.record).map(\.id).contains("hevc"))
        #expect(model.record.family == .hevc)

        // The lens keeps only its H.264 options.
        var changed = capabilities
        changed.videoOptions = capabilities.videoOptions.filter { $0.lensID != lens || $0.codec.family == .h264 }
        model.replaceCapabilities(changed)
        #expect(model.lensID == lens)
        #expect(model.recordResolver.chips(.codec, for: model.record).map(\.id) == ["h264"])
        #expect(model.record.family == .h264)
        #expect(model.currentVideoOption?.codec.family == .h264)

        // The lens loses every option.
        var bare = changed
        bare.videoOptions = changed.videoOptions.filter { $0.lensID != lens }
        model.replaceCapabilities(bare)
        #expect(model.recordResolver.chips(.codec, for: model.record).isEmpty)
        #expect(model.currentVideoOption == nil)
    }
}
