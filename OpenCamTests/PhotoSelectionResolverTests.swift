import Testing
@testable import OpenCam

@Suite struct PhotoSelectionResolverTests {
    func resolver(_ id: String) throws -> PhotoSelectionResolver {
        let caps = try Fixture.load(); return PhotoSelectionResolver(options: caps.photoOptions, lenses: caps.lenses, lensID: id)
    }
    @Test func rawIsDimmedOnTheTwoTimesLensWithLensNames() throws {
        let chips = try resolver("wide@2").chips(.format, for: PhotoSelection(format: .heif, megapixels: 12))
        #expect(chips.map(\.id) == ["RAW", "RAW + HEIF", "HEIF"])
        #expect(chips[0].reason == "RAW needs the 0.5x or 1x lens."); #expect(chips[1].reason == "RAW needs the 0.5x or 1x lens.")
        #expect(chips[2].isAvailable)
    }
    @Test func lensSwitchAndDefault() throws {
        #expect(try resolver("wide@2").settled(PhotoSelection(format: .raw, megapixels: 48)) == PhotoSelection(format: .heif, megapixels: 12))
        #expect(try resolver("wide").defaultSelection() == PhotoSelection(format: .rawPlusHEIF, megapixels: 48))
    }
    @Test func reasonLineIsTheFirstDimmedChipsReason() throws {
        #expect(try resolver("wide@2").reasonLine(.format, for: PhotoSelection(format: .heif, megapixels: 12)) == "RAW needs the 0.5x or 1x lens.")
        #expect(try resolver("wide").reasonLine(.format, for: PhotoSelection(format: .heif, megapixels: 48)) == nil)
    }
    @Test func resolutionChipsUseMegapixelIDs() throws {
        let chips = try resolver("wide").chips(.resolution, for: PhotoSelection(format: .heif, megapixels: 48))
        #expect(chips.map(\.id) == ["48", "12"])
        #expect(chips.filter(\.isAvailable).count == 2)
    }
}
