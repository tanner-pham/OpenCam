import Foundation
import Testing
@testable import OpenCam

@Suite struct CapabilityMapperTests {
    let wide = Lens(id: "W", kind: .wide, deviceUniqueID: "W", zoomFactor: 1, label: "1x"), tele = Lens(id: "W@2", kind: .wide, deviceUniqueID: "W", zoomFactor: 2, label: "2x")
    func fmt(_ w: Int, _ h: Int, _ ranges: [ClosedRange<Double>], _ codecs: [Int: [String]]) -> FormatDescriptor {
        FormatDescriptor(lensID: "W", width: w, height: h, isBinned: false, frameRateRanges: ranges, codecTypesByColourSpace: codecs,
                         allowsCompressionProperties: true, maxPhotoDimensions: [PhotoSize(width: 8064, height: 6048)], hasBayerRAW: true)
    }
    @Test func codecsMapAndUnknownsDrop() {
        #expect(CapabilityMapper.codecs(fourCCs: ["apch", "jpeg", "hvc1"], allowsCompressionProperties: false).map(\.quality) == ["422 HQ", "Standard"])
        #expect(CapabilityMapper.codecs(fourCCs: ["hvc1"], allowsCompressionProperties: true).map(\.quality) == ["Max", "High", "Medium", "Low"])
    }
    @Test func everyCombinationIsListedOnce() {
        let f = fmt(3840, 2160, [1...30], [0: ["apch"], 3: ["apch"]])
        let options = CapabilityMapper.videoOptions(from: [f, f])
        #expect(options.count == 6); #expect(Set(options.map(\.colour)) == [.rec709, .appleLog])
    }
    @Test func twoTimesLensCopiesVideoButNotRaw() {
        let caps = CapabilityMapper.capabilities(lenses: [wide, tele], formats: [fmt(1920, 1080, [1...60], [0: ["hvc1"]])], osBuild: "B", modelIdentifier: "M")
        #expect(caps.videoOptions(forLens: "W@2").count == caps.videoOptions(forLens: "W").count)
        #expect(caps.photoOptions(forLens: "W@2").map(\.format) == [.heif])
        #expect(Set(caps.photoOptions(forLens: "W").map(\.format)) == [.raw, .rawPlusHEIF, .heif])
    }
}
