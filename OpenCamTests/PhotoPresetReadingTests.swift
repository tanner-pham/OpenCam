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
        // Through the existing mapper: RAW and RAW + HEIF on the 1x lens (at the preset format's own 12 MP only), HEIF only
        // on its 2x crop.
        let reading = PhotoPresetReading(width: 4032, height: 3024, sizes: [twelve, fortyEight], hasBayerRAW: true)
        let formats = PhotoPresetReading.assign(reading, to: [descriptor(4032, 3024, sizes: [twelve])])
        let wide = Lens(id: "wide", kind: .wide, deviceUniqueID: "d", zoomFactor: 1, label: "1x")
        let crop = Lens(id: "wide@2", kind: .wide, deviceUniqueID: "d", zoomFactor: 2, label: "2x")
        let options = CapabilityMapper.photoOptions(from: formats, lenses: [wide, crop])
        #expect(Set(options.filter { $0.lensID == "wide" }.map(\.format)) == Set(PhotoFormat.allCases))
        #expect(Set(options.filter { $0.lensID == "wide@2" }.map(\.format)) == [.heif])
        #expect(Set(options.map { $0.width * $0.height }) == [4032 * 3024, 8064 * 6048])
        #expect(Set(options.filter { $0.format.includesRAW }.map { $0.width * $0.height }) == [4032 * 3024])
    }
    /// Measured on the Duo: under the photo preset a RAW + HEIF capture at "48 MP" wrote a 4032 x 3024 DNG and HEIC, while
    /// HEIF alone wrote 8064 x 6048. RAW is offered only at the preset format's own size; HEIF keeps every listed size.
    @Test func rawIsOfferedOnlyAtThePresetFormatsOwnSize() {
        let twentyFour = PhotoSize(width: 5712, height: 4284)
        let reading = PhotoPresetReading(width: 4032, height: 3024, sizes: [twelve, twentyFour, fortyEight], hasBayerRAW: true)
        let formats = PhotoPresetReading.assign(reading, to: [descriptor(1920, 1080, sizes: [twelve]), descriptor(4032, 3024, sizes: [twelve])])
        #expect(formats.map(\.rawPhotoSize) == [nil, twelve])
        let wide = Lens(id: "wide", kind: .wide, deviceUniqueID: "d", zoomFactor: 1, label: "1x")
        let options = CapabilityMapper.photoOptions(from: formats, lenses: [wide])
        let sizes = { (format: PhotoFormat) in Set(options.filter { $0.format == format }.map { PhotoSize(width: $0.width, height: $0.height) }) }
        #expect(sizes(.heif) == [twelve, twentyFour, fortyEight])
        #expect(sizes(.raw) == [twelve]); #expect(sizes(.rawPlusHEIF) == [twelve])
        // Without a preset reading the formats' own fields stand: RAW at every size the RAW format lists.
        let own = CapabilityMapper.photoOptions(from: [descriptor(4032, 3024, sizes: [twelve, fortyEight], raw: true)], lenses: [wide])
        #expect(Set(own.filter { $0.format == .raw }.map { $0.width * $0.height }) == [4032 * 3024, 8064 * 6048])
    }
    @Test func aSavedRAWPlusHEIFAt48MPSettlesTo12MP() {
        let reading = PhotoPresetReading(width: 4032, height: 3024, sizes: [twelve, fortyEight], hasBayerRAW: true)
        let wide = Lens(id: "wide", kind: .wide, deviceUniqueID: "d", zoomFactor: 1, label: "1x")
        let options = CapabilityMapper.photoOptions(from: PhotoPresetReading.assign(reading, to: [descriptor(4032, 3024, sizes: [twelve])]), lenses: [wide])
        let resolver = PhotoSelectionResolver(options: options, lenses: [wide], lensID: "wide")
        #expect(resolver.settled(PhotoSelection(format: .rawPlusHEIF, megapixels: 48)) == PhotoSelection(format: .rawPlusHEIF, megapixels: 12))
        #expect(resolver.settled(PhotoSelection(format: .heif, megapixels: 48)) == PhotoSelection(format: .heif, megapixels: 48))
    }
}
