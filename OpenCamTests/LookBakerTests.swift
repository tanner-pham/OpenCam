import CoreImage
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import OpenCam

@Suite struct LookBakerTests {
    @Test func bakedHEIFIsUprightDisplayP3WithTheLookAndTheMetadata() throws {
        let url = try TestFiles.directory().appending(path: "source.HEIC")
        let exif: [CFString: Any] = [kCGImagePropertyExifDateTimeOriginal: "2026:11:10 09:30:00"]
        let tiff: [CFString: Any] = [kCGImagePropertyTIFFMake: "Apple", kCGImagePropertyTIFFModel: "iPhone Duo"]
        _ = try TestFiles.writeOrientedPicture(width: 400, height: 300, orientation: 6, type: .heic,
                                               metadata: [kCGImagePropertyExifDictionary: exif, kCGImagePropertyTIFFDictionary: tiff], to: url)
        let baked = try LookBaker.bake(try Data(contentsOf: url), adjustments: Adjustments().setting(.saturation, to: -100))
        let source = try #require(CGImageSourceCreateWithData(baked as CFData, nil))
        #expect(CGImageSourceGetType(source) as String? == UTType.heic.identifier)
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect((properties[kCGImagePropertyOrientation] as? Int ?? 1) == 1)
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == 300); #expect(properties[kCGImagePropertyPixelHeight] as? Int == 400)
        #expect((properties[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifDateTimeOriginal] as? String == "2026:11:10 09:30:00")
        #expect((properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFModel] as? String == "iPhone Duo")
        #expect(try #require(CGImageSourceCreateImageAtIndex(source, 0, nil)).colorSpace?.name == CGColorSpace.displayP3)
        // Upright, red was the top half; saturation -100 makes it grey.
        let top = try PixelReader.rgb(try #require(CIImage(data: baked)), x: 150, y: 300)
        #expect(abs(top.x - top.y) < 0.03); #expect(abs(top.x - top.z) < 0.03)
    }
    @Test func undecodableDataThrows() {
        #expect(throws: LookBakeError.undecodable) { try LookBaker.bake(Data("not a photo".utf8), adjustments: Adjustments()) }
    }
}
