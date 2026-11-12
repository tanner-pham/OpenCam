import Foundation
import Testing
@testable import OpenCam

@Suite struct WriterOptionsTests {
    static let wide = "com.apple.avfoundation.avcapturedevice.built-in_video:0"

    func derived(_ support: WriterSupport) throws -> [VideoOption] {
        WriterOptions.derived(from: try Fixture.loadDuo().videoOptions, support: support)
    }

    func selection(_ option: VideoOption) -> RecordSelection {
        RecordSelection(family: option.codec.family, quality: option.codec.quality, resolution: option.resolution,
                        frameRate: option.frameRate, colour: option.colour)
    }

    @Test func thePhoneGainsProResAndLogWhereItHasHLG() throws {
        let all = try derived(.all)
        #expect(all.count == 1_776)
        let wideOptions = all.filter { $0.lensID == Self.wide }
        #expect(wideOptions.count == 288)
        let proRes = wideOptions.filter { $0.codec.family == .proRes }
        #expect(proRes.count == 216)
        for colour in [ColourMode.hlg, .log, .rec709] { #expect(proRes.filter { $0.colour == colour }.count == 72, "\(colour)") }
        let hevc = wideOptions.filter { $0.codec.family == .hevc }
        #expect(hevc.count == 72)
        #expect(hevc.allSatisfy { $0.colour == .log })
        #expect(Set(wideOptions.map(\.resolution.id)) == ["3840x2160", "1920x1440", "1920x1080", "1280x720"])
        #expect(wideOptions.map(\.frameRate).max() == 60)
        #expect(Set(proRes.map(\.codec.quality)) == ["422 HQ", "422", "422 LT", "422 Proxy"])
        #expect(!all.contains { $0.codec.family == .h264 || $0.colour == .p3 || $0.frameRate > 60 })
    }

    @Test func everyDerivedOptionHasAScannedHEVCOptionInHLGAtItsLensSizeAndRate() throws {
        let scanned = try Fixture.loadDuo().videoOptions
        let hlg = Set(scanned.filter { $0.codec.family == .hevc && $0.colour == .hlg }.map { [$0.lensID, $0.resolution.id, String($0.frameRate)] })
        for option in try derived(.all) {
            #expect(hlg.contains([option.lensID, option.resolution.id, String(option.frameRate)]), "\(option)")
        }
    }

    @Test func nothingScannedIsDerivedAgain() throws {
        let scanned = try Fixture.load().videoOptions
        #expect(scanned.contains { $0.codec.family == .proRes && $0.colour == .hlg })
        let held = Set(scanned)
        #expect(!WriterOptions.derived(from: scanned, support: .all).contains { held.contains($0) })
        let duo = try Fixture.loadDuo().videoOptions
        #expect(Set(WriterOptions.derived(from: duo, support: .all)).isDisjoint(with: Set(duo)))
    }

    @Test func supportGatesWhatIsDerived() throws {
        #expect(try derived([]).isEmpty)
        let hlgOnly = try derived([.proRes])
        #expect(hlgOnly.count == 444)
        #expect(hlgOnly.allSatisfy { $0.codec.family == .proRes && $0.colour == .hlg })
        #expect(try derived([.proRes, .proResSDR]).count == 888)
        #expect(try derived(.all).count == 1_776)
    }

    @Test func theMaximumFrameRateIsOneNumber() {
        #expect(WriterOptions.maximumFrameRate == 60)
        let size = Resolution.named(width: 3840, height: 2160)
        // 4K (and anything above 1080p's pixel count) is offered up to 30 fps until the second on-device check measures more.
        #expect(WriterOptions.largeSizeMaximumFrameRate == 30)
        #expect(WriterOptions.isOffered(quality: "422 HQ", resolution: size, frameRate: 30, colour: .hlg))
        #expect(!WriterOptions.isOffered(quality: "422 HQ", resolution: size, frameRate: 48, colour: .hlg))
        #expect(!WriterOptions.isOffered(quality: "422 HQ", resolution: size, frameRate: 60, colour: .hlg))
        let uhdPortraitBinned = Resolution.named(width: 1920, height: 1440)
        #expect(!WriterOptions.isOffered(quality: "422", resolution: uhdPortraitBinned, frameRate: 60, colour: .hlg))
        for name in [(1920, 1080), (1280, 720)] {
            let small = Resolution.named(width: name.0, height: name.1)
            #expect(WriterOptions.isOffered(quality: "422 HQ", resolution: small, frameRate: 60, colour: .hlg))
            #expect(!WriterOptions.isOffered(quality: "422 HQ", resolution: small, frameRate: 120, colour: .hlg))
        }
    }

    @Test func shippedSupportIsOnlyWhatIsWired() {
        #expect(WriterSupport.shipped(isSimulator: true) == .all)
        // Task 6 wires the recording of ProRes in HLG and in Rec. 709. The baked Log profile joins in Task 9.
        #expect(WriterSupport.shipped(isSimulator: false) == [.proRes, .proResSDR])
        #expect(!WriterSupport.shipped(isSimulator: false).contains(.log))
    }

    @Test func writerOptionsAreNeverEncoded() throws {
        var scanned = try Fixture.loadDuo()
        scanned.scanVersion = CaptureCapabilities.currentScanVersion   // the cache reuses only the current version
        let merged = scanned.withWriterOptions(.all)
        #expect(merged.writerOptions.count == 1_776)
        #expect(scanned.writerOptions.isEmpty)
        #expect(try merged.encoded() == scanned.encoded())
        let directory = try TestFiles.directory()
        try CapabilityCache(directory: directory).save(merged)
        let loaded = try #require(CapabilityCache(directory: directory).load(osBuild: merged.osBuild, modelIdentifier: merged.modelIdentifier))
        #expect(loaded.videoOptions.count == 6_192)
        #expect(loaded.writerOptions.isEmpty)
        #expect(CaptureCapabilities.currentScanVersion == 3)
    }

    @Test func recorderFollowsTheOption() throws {
        let capabilities = try Fixture.loadDuo().withWriterOptions(.all)
        let lens = try #require(capabilities.lenses.first { $0.id == Self.wide })
        let resolver = RecordSelectionResolver(options: capabilities.videoOptions, writerOptions: capabilities.writerOptions, lens: lens)
        let size = Resolution.named(width: 3840, height: 2160)
        func pick(_ family: CodecFamily, _ quality: String, _ colour: ColourMode) -> RecordSelection {
            RecordSelection(family: family, quality: quality, resolution: size, frameRate: 30, colour: colour)
        }
        for system in [pick(.hevc, "High", .rec709), pick(.hevc, "High", .hlg)] {
            #expect(resolver.option(for: system) != nil)
            #expect(resolver.recorder(for: system) == .system)
        }
        for writer in [pick(.proRes, "422 HQ", .hlg), pick(.hevc, "High", .log)] {
            #expect(resolver.option(for: writer) != nil)
            #expect(resolver.recorder(for: writer) == .writer)
        }
    }

    @Test func aTieSettlesOnTheScannedOption() throws {
        let capabilities = try Fixture.loadDuo()
        let scanned = try #require(capabilities.videoOptions.first { $0.lensID == Self.wide })
        let resolver = RecordSelectionResolver(lensOptions: [scanned], writerOptions: [scanned])
        #expect(resolver.recorder(for: selection(scanned)) == .system)
    }

    @Test func writerOptionsAreInTheMappersRowOrder() throws {
        let options = try derived(.all).filter { $0.lensID == Self.wide }
        let qualities = options.filter { $0.codec.family == .proRes && $0.colour == .hlg && $0.frameRate == 30 && $0.resolution.id == "3840x2160" }
        #expect(qualities.map(\.codec.quality) == ["422 HQ", "422", "422 LT", "422 Proxy"])
        #expect(options.first?.codec.family == .proRes)   // CodecFamily order: ProRes rows precede HEVC rows
    }
}
