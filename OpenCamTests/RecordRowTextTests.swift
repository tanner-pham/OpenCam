import Foundation
import Testing
@testable import OpenCam

@Suite struct RecordRowTextTests {
    static let wide = "com.apple.avfoundation.avcapturedevice.built-in_video:0"
    static let size = Resolution.named(width: 3840, height: 2160)

    func phoneResolver() throws -> RecordSelectionResolver {
        let capabilities = try Fixture.loadDuo().withWriterOptions(.all)
        let lens = try #require(capabilities.lenses.first { $0.id == Self.wide })
        return RecordSelectionResolver(options: capabilities.videoOptions, writerOptions: capabilities.writerOptions, lens: lens)
    }

    func pick(_ family: CodecFamily, _ quality: String, _ colour: ColourMode) -> RecordSelection {
        RecordSelection(family: family, quality: quality, resolution: Self.size, frameRate: 30, colour: colour)
    }

    func shown(_ row: RecordRow, _ resolver: RecordSelectionResolver, _ selection: RecordSelection) -> [Chip] {
        RecordRowText.chips(row, from: resolver.chips(row, for: selection))
    }

    func line(_ row: RecordRow, _ resolver: RecordSelectionResolver, _ selection: RecordSelection) -> String? {
        RecordRowText.line(row, chips: shown(row, resolver, selection), selection: selection)
    }

    @Test func logCarriesItsDetailAndAppleLogIsListedDimmed() throws {
        let chips = shown(.colour, try phoneResolver(), pick(.hevc, "High", .rec709))
        #expect(chips.map(\.id) == ["Rec. 709", "P3", "HLG", "Log", "Apple Log"])
        let log = try #require(chips.first { $0.id == "Log" })
        #expect(log.isAvailable); #expect(log.detail == "baked curve")
        let appleLog = try #require(chips.last)
        #expect(!appleLog.isAvailable); #expect(appleLog.reason == RecordRowText.appleLogUnavailable)
        #expect(chips.filter { $0.id != "Log" }.allSatisfy { $0.detail == nil })
    }

    @Test func appleLogIsNotAddedWhereTheLensHasIt() throws {
        let capabilities = try Fixture.load()
        let lens = try #require(capabilities.lenses.first { $0.id == "wide" })
        let resolver = RecordSelectionResolver(options: capabilities.videoOptions, lens: lens)
        let selection = pick(.hevc, "High", .rec709)
        let chips = resolver.chips(.colour, for: selection)
        #expect(chips.contains { $0.id == "Apple Log 2" })
        #expect(RecordRowText.chips(.colour, from: chips) == chips)
    }

    @Test func theLineUnderColour() throws {
        let resolver = try phoneResolver()
        #expect(line(.colour, resolver, pick(.hevc, "High", .log)) == RecordRowText.logNote)
        #expect(line(.colour, resolver, pick(.hevc, "High", .rec709)) == RecordRowText.appleLogUnavailable)
        #expect(line(.colour, resolver, pick(.proRes, "422 HQ", .hlg)) == "P3 is not available with ProRes.")
    }

    @Test func theLineUnderQuality() throws {
        let resolver = try phoneResolver()
        #expect(line(.quality, resolver, pick(.proRes, "422 HQ", .hlg)) == RecordRowText.proResNote)
        #expect(line(.quality, resolver, pick(.proRes, "422 HQ", .rec709)) == RecordRowText.proResSDRNote)
        #expect(line(.quality, resolver, pick(.hevc, "High", .rec709)) == nil)
    }

    @Test func otherRowsAreUntouched() throws {
        let resolver = try phoneResolver()
        let selection = pick(.hevc, "High", .rec709)
        for row in [RecordRow.codec, .quality, .resolution, .frameRate] {
            let chips = resolver.chips(row, for: selection)
            #expect(RecordRowText.chips(row, from: chips) == chips)
            #expect(RecordRowText.line(row, chips: chips, selection: selection) == chips.first { !$0.isAvailable }?.reason)
        }
    }

    @Test func noStringHasAnEmDash() {
        let strings = [RecordRowText.logDetail, RecordRowText.logNote, RecordRowText.appleLogUnavailable,
                       RecordRowText.proResNote, RecordRowText.proResSDRNote]
        for text in strings { #expect(!text.contains("\u{2014}"), "\(text)") }
    }

    @Test func thePhoneFormatsFlagStripsWhatThePhoneLacks() throws {
        let stripped = try Fixture.load().asThePhoneScans()
        #expect(!stripped.videoOptions.isEmpty)
        #expect(!stripped.videoOptions.contains { $0.codec.family == .proRes || $0.codec.family == .raw })
        #expect(!stripped.videoOptions.contains { $0.colour == .appleLog || $0.colour == .appleLog2 })
        #expect(stripped.writerOptions.isEmpty)
        #expect(!stripped.withWriterOptions(.all).writerOptions.isEmpty)
    }
}
