import Testing
@testable import OpenCam

@Suite struct RecordSelectionResolverTests {
    let uhd = Resolution.named(width: 3840, height: 2160), fhd = Resolution.named(width: 1920, height: 1080)
    func resolver(_ id: String) throws -> RecordSelectionResolver {
        let caps = try Fixture.load(); return RecordSelectionResolver(options: caps.videoOptions, lens: caps.lenses.first { $0.id == id })
    }
    @Test func frameRatesAboveTheLimitAreDimmedWithAComputedReason() throws {
        let s = RecordSelection(family: .proRes, quality: "422 HQ", resolution: uhd, frameRate: 30, colour: .appleLog2)
        let chips = try resolver("wide").chips(.frameRate, for: s)
        #expect(chips.map(\.id) == ["24", "25", "30", "48", "50", "60", "100", "120"])
        #expect(chips.filter(\.isAvailable).map(\.id) == ["24", "25", "30"])
        #expect(try resolver("wide").reasonLine(.frameRate, for: s) == "ProRes 422 HQ at 4K records at up to 30 fps.")
    }
    @Test func colourReasonsComeFromTheData() throws {
        let h264 = RecordSelection(family: .h264, quality: "Max", resolution: fhd, frameRate: 30, colour: .rec709)
        #expect(try resolver("wide").chips(.colour, for: h264).first { $0.id == "HLG" }?.reason == "HLG is not available with H.264.")
        let hevc120 = RecordSelection(family: .hevc, quality: "Max", resolution: fhd, frameRate: 120, colour: .rec709)
        #expect(try resolver("wide").chips(.colour, for: hevc120).first { $0.id == "Apple Log 2" }?.reason == "Apple Log 2 is not available at 120 fps.")
    }
    @Test func rowsListOnlyThisLensAndFamily() throws {
        let s = RecordSelection(family: .hevc, quality: "High", resolution: uhd, frameRate: 30, colour: .rec709)
        #expect(try resolver("wide").chips(.quality, for: s).map(\.id) == ["Max", "High", "Medium", "Low"])
        #expect(try resolver("outer").chips(.codec, for: s).map(\.id) == ["hevc", "h264"])
    }
    @Test func changingFamilyMovesLowerRowsToNearestValid() throws {
        let s = RecordSelection(family: .hevc, quality: "Max", resolution: fhd, frameRate: 120, colour: .rec709)
        #expect(try resolver("wide").select(.codec, chipID: "proRes", in: s) == RecordSelection(family: .proRes, quality: "422 HQ", resolution: fhd, frameRate: 60, colour: .rec709))
    }
    @Test func lensWithoutSelectionMovesToNearestValid() throws {
        let s = RecordSelection(family: .proRes, quality: "422 HQ", resolution: uhd, frameRate: 30, colour: .appleLog2)
        #expect(try resolver("ultraWide").settled(s) == RecordSelection(family: .proRes, quality: "422 HQ", resolution: fhd, frameRate: 30, colour: .appleLog2))
        let outer = try resolver("outer"), front = outer.settled(s)
        #expect(front == RecordSelection(family: .hevc, quality: "Max", resolution: fhd, frameRate: 30, colour: .rec709))
        #expect(front.flatMap { outer.option(for: $0) } != nil)
    }
    @Test func lensWithNoOptionsReturnsNil() throws {
        let s = RecordSelection(family: .hevc, quality: "Max", resolution: fhd, frameRate: 30, colour: .rec709)
        #expect(RecordSelectionResolver(options: try Fixture.load().videoOptions, lens: nil).settled(s) == nil)
    }
    @Test func defaultIsHEVCHigh4K30() throws {
        #expect(try resolver("wide").defaultSelection() == RecordSelection(family: .hevc, quality: "High", resolution: uhd, frameRate: 30, colour: .rec709))
    }

    private let free: Int64 = 141_000_000_000
    private func estimateText(_ resolver: RecordSelectionResolver, _ row: RecordRow, _ chipID: String, in selection: RecordSelection) throws -> ChipEstimate {
        let settled = try #require(resolver.select(row, chipID: chipID, in: selection))
        let option = try #require(resolver.option(for: settled))
        return DataRateEstimator.estimate(for: option, freeBytes: free)
    }
    @Test func availableCodecAndQualityChipsCarryTheSettledEstimate() throws {
        let wide = try resolver("wide")
        let s = RecordSelection(family: .hevc, quality: "High", resolution: uhd, frameRate: 30, colour: .rec709)
        for row in [RecordRow.codec, .quality] {
            let chips = wide.chips(row, for: s, freeBytes: free)
            #expect(chips.contains { $0.isAvailable })
            for chip in chips {
                if chip.isAvailable {
                    #expect(chip.estimate == (try estimateText(wide, row, chip.id, in: s)))
                } else {
                    #expect(chip.estimate == nil)
                }
            }
        }
        for row in [RecordRow.resolution, .frameRate, .colour] {
            #expect(wide.chips(row, for: s, freeBytes: free).allSatisfy { $0.estimate == nil })
            #expect(wide.chips(row, for: s, freeBytes: free) == wide.chips(row, for: s))
        }
    }
    @Test func withoutFreeSpaceNothingChanges() throws {
        let wide = try resolver("wide")
        let s = RecordSelection(family: .hevc, quality: "High", resolution: uhd, frameRate: 30, colour: .rec709)
        for row in RecordRow.allCases {
            #expect(wide.chips(row, for: s, freeBytes: nil) == wide.chips(row, for: s))
            #expect(wide.chips(row, for: s).allSatisfy { $0.estimate == nil })
        }
    }
    @Test func aCodecTapThatMovesTheOtherRowsShowsTheSettledEstimate() throws {
        let wide = try resolver("wide")
        let s = RecordSelection(family: .hevc, quality: "Max", resolution: fhd, frameRate: 120, colour: .rec709)
        let settled = try #require(wide.select(.codec, chipID: "proRes", in: s))
        #expect(settled.frameRate != s.frameRate)
        let chip = try #require(wide.chips(.codec, for: s, freeBytes: free).first { $0.id == "proRes" })
        let expected = DataRateEstimator.estimate(for: try #require(wide.option(for: settled)), freeBytes: free)
        #expect(chip.estimate == expected)
    }
}
