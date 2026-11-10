import Testing
@testable import OpenCam

@Suite struct PhotoPresetReadingTests {
    func descriptor(_ width: Int, _ height: Int, sizes: [PhotoSize], raw: Bool = false) -> FormatDescriptor {
        FormatDescriptor(lensID: "wide", width: width, height: height, isBinned: false, frameRateRanges: [1...60],
                         codecTypesByColourSpace: [0: ["hvc1"]], allowsCompressionProperties: true,
                         maxPhotoDimensions: sizes, hasBayerRAW: raw)
    }
    let tiny = PhotoSize(width: 192, height: 144), twelve = PhotoSize(width: 4032, height: 3024), fortyEight = PhotoSize(width: 8064, height: 6048)

    @Test func onlyThePresetsSizesAreOffered() {   // Review Focus 3
        let reading = PhotoPresetReading(width: 4032, height: 3024, sizes: [twelve, fortyEight], hasBayerRAW: true)
        let out = PhotoPresetReading.assign(reading, to: [descriptor(192, 144, sizes: [tiny, twelve]), descriptor(4032, 3024, sizes: [twelve]),
                                                          descriptor(3840, 2160, sizes: [twelve])])
        #expect(out.map(\.maxPhotoDimensions) == [[], [twelve, fortyEight], []])
        #expect(out.map(\.hasBayerRAW) == [false, true, false])
        #expect(out.map(\.width) == [192, 4032, 3840])          // nothing else about a descriptor changes
    }
    @Test func frontLensWithoutRAWGetsHEIFOnly() {   // Review Focus 1
        let reading = PhotoPresetReading(width: 2016, height: 1512, sizes: [twelve], hasBayerRAW: false)
        let out = PhotoPresetReading.assign(reading, to: [descriptor(2016, 1512, sizes: [twelve], raw: true)])
        #expect(out.map(\.hasBayerRAW) == [false]); #expect(out[0].maxPhotoDimensions == [twelve])
    }
    @Test func aReadingWithNoMatchingFormatUsesTheFirstDescriptor() {
        let reading = PhotoPresetReading(width: 4224, height: 2376, sizes: [fortyEight], hasBayerRAW: true)
        let out = PhotoPresetReading.assign(reading, to: [descriptor(1920, 1080, sizes: [twelve]), descriptor(3840, 2160, sizes: [twelve])])
        #expect(out.map(\.maxPhotoDimensions) == [[fortyEight], []]); #expect(out.map(\.hasBayerRAW) == [true, false])
    }
    @Test func noPresetReadingKeepsTheFormatsOwnPhotoFields() {   // Review Focus 4
        let before = [descriptor(192, 144, sizes: [tiny]), descriptor(4032, 3024, sizes: [twelve], raw: true)]
        #expect(PhotoPresetReading.assign(nil, to: before) == before)
        #expect(PhotoPresetReading.assign(PhotoPresetReading(width: 1, height: 1, sizes: [], hasBayerRAW: false), to: []).isEmpty)
    }
    @Test func theMapperOffersRAWOnlyOnTheUnzoomedLens() {
        // Through the existing mapper: RAW and RAW + HEIF at both sizes on the 1x lens, HEIF only on its 2x crop.
        let reading = PhotoPresetReading(width: 4032, height: 3024, sizes: [twelve, fortyEight], hasBayerRAW: true)
        let formats = PhotoPresetReading.assign(reading, to: [descriptor(4032, 3024, sizes: [twelve])])
        let wide = Lens(id: "wide", kind: .wide, deviceUniqueID: "d", zoomFactor: 1, label: "1x")
        let crop = Lens(id: "wide@2", kind: .wide, deviceUniqueID: "d", zoomFactor: 2, label: "2x")
        let options = CapabilityMapper.photoOptions(from: formats, lenses: [wide, crop])
        #expect(Set(options.filter { $0.lensID == "wide" }.map(\.format)) == Set(PhotoFormat.allCases))
        #expect(Set(options.filter { $0.lensID == "wide@2" }.map(\.format)) == [.heif])
        #expect(Set(options.map { $0.width * $0.height }) == [4032 * 3024, 8064 * 6048])
    }
}
