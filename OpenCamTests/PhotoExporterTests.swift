import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import OpenCam

@Suite struct PhotoExporterTests {
    @Test func exportsFullSizeJPEGOutsideCaptures() async throws {
        let captures = try TestFiles.directory(), out = try TestFiles.directory()
        _ = try TestFiles.writeJPEG(width: 3000, height: 2000, rgb: SIMD3(0.5, 0.5, 0.5), to: captures.appending(path: "OC_0001.JPG"))
        let before = try TestFiles.snapshot(captures)
        let item = try #require(LibraryScanner.items(in: captures).first)
        let url = try await PhotoExporter(directory: out).export(item, edit: PhotoEdit(adjustments: Adjustments().setting(.exposure, to: 1)))
        #expect(url.lastPathComponent == "OC_0001-edited.JPG")
        #expect(url.deletingLastPathComponent().standardizedFileURL == out.standardizedFileURL)
        #expect(try PictureDecoder.pixelSize(at: url) == CGSize(width: 3000, height: 2000))
        #expect(abs(try PixelReader.rgb(PictureDecoder.full(at: url), x: 1500, y: 1000).x - 0.686) < 0.02)
        #expect(try TestFiles.snapshot(captures) == before)
    }

    @Test func heicOriginalExportsAsHEIF() async throws {
        let captures = try TestFiles.directory()
        _ = try TestFiles.writeHEIC(width: 400, height: 300, rgb: SIMD3(0.4, 0.5, 0.6), to: captures.appending(path: "OC_0002.HEIC"))
        let item = try #require(LibraryScanner.items(in: captures).first)
        let url = try await PhotoExporter(directory: try TestFiles.directory()).export(item, edit: PhotoEdit())
        #expect(url.lastPathComponent == "OC_0002-edited.HEIC"); #expect(try PictureDecoder.pixelSize(at: url) == CGSize(width: 400, height: 300))
        #expect(ExportFormat.of(URL(filePath: "/x/OC_0003.jpeg")) == .jpeg); #expect(ExportFormat.of(URL(filePath: "/x/OC_0003.DNG")) == .heif)
    }

    @Test func missingSourceThrows() async throws {   // Review Focus 5
        let captures = try TestFiles.directory()
        _ = try TestFiles.writeJPEG(width: 40, height: 30, rgb: SIMD3(0.5, 0.5, 0.5), to: captures.appending(path: "OC_0004.JPG"))
        let item = try #require(LibraryScanner.items(in: captures).first)
        try FileManager.default.removeItem(at: item.pictureURL)
        await #expect(throws: ExportError.sourceMissing(path: item.pictureURL.path(percentEncoded: false))) {
            try await PhotoExporter(directory: try TestFiles.directory()).export(item, edit: PhotoEdit())
        }
    }

    /// A portrait original stored on its side (EXIF orientation 6) exports upright with no orientation tag, in Display P3,
    /// as JPEG and as HEIF.
    @Test(arguments: [ExportFormat.jpeg, .heif])
    func portraitOriginalExportsUprightInDisplayP3(format: ExportFormat) async throws {
        let captures = try TestFiles.directory()
        let original = captures.appending(path: "OC_0005." + format.rawValue)
        _ = try TestFiles.writeOrientedPicture(width: 400, height: 300, orientation: 6, type: format == .jpeg ? .jpeg : .heic, to: original)
        let item = try #require(LibraryScanner.items(in: captures).first)
        let url = try await PhotoExporter(directory: try TestFiles.directory()).export(item, edit: PhotoEdit())
        #expect(url.lastPathComponent == "OC_0005-edited." + format.rawValue)

        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect((properties[kCGImagePropertyOrientation] as? Int ?? 1) == 1)
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == 300); #expect(properties[kCGImagePropertyPixelHeight] as? Int == 400)
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.colorSpace?.name == CGColorSpace.displayP3)

        // Core Image rows count from the bottom: upright, red is on top and blue below.
        let decoded = try PictureDecoder.full(at: url)
        let top = try PixelReader.rgb(decoded, x: 150, y: 300), bottom = try PixelReader.rgb(decoded, x: 150, y: 100)
        #expect(top.x > 0.9); #expect(top.z < 0.1)
        #expect(bottom.z > 0.9); #expect(bottom.x < 0.1)
    }

    @Test func exportReplacesAnOlderExportOfTheSameName() async throws {
        let captures = try TestFiles.directory(), out = try TestFiles.directory()
        _ = try TestFiles.writeJPEG(width: 40, height: 30, rgb: SIMD3(0.5, 0.5, 0.5), to: captures.appending(path: "OC_0006.JPG"))
        let item = try #require(LibraryScanner.items(in: captures).first)
        let exporter = PhotoExporter(directory: out)
        _ = try await exporter.export(item, edit: PhotoEdit(adjustments: Adjustments().setting(.exposure, to: 1)))
        let url = try await exporter.export(item, edit: PhotoEdit())
        #expect(abs(try PixelReader.rgb(PictureDecoder.full(at: url), x: 20, y: 15).x - 0.5) < 0.02)
        #expect(try FileManager.default.contentsOfDirectory(atPath: out.path(percentEncoded: false)) == ["OC_0006-edited.JPG"])
    }

    @Test func undecodableSourceThrows() async throws {
        let captures = try TestFiles.directory()
        try Data("not a picture".utf8).write(to: captures.appending(path: "OC_0007.JPG"))
        let item = try #require(LibraryScanner.items(in: captures).first)
        await #expect(throws: ExportError.undecodable(path: item.pictureURL.path(percentEncoded: false))) {
            try await PhotoExporter(directory: try TestFiles.directory()).export(item, edit: PhotoEdit())
        }
    }

    @Test func appDefaultExportsIntoTmpExport() async throws {
        let captures = try TestFiles.directory()
        _ = try TestFiles.writeJPEG(width: 40, height: 30, rgb: SIMD3(0.5, 0.5, 0.5), to: captures.appending(path: "OC_0008.JPG"))
        let item = try #require(LibraryScanner.items(in: captures).first)
        let url = try await PhotoExporter.appDefault().export(item, edit: PhotoEdit())
        defer { try? FileManager.default.removeItem(at: url) }
        let expected = FileManager.default.temporaryDirectory.appending(path: "Export", directoryHint: .isDirectory)
        #expect(url.deletingLastPathComponent().standardizedFileURL == expected.standardizedFileURL)
    }
}
