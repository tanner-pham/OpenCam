import CoreImage
import Foundation
import Testing
@testable import OpenCam

@Suite struct MaskRenderTests {
    let renderer = LookRenderer.shared
    let size = 100

    func grey() throws -> CIImage { try TestFiles.patch(SIMD3(repeating: 0.4), size: size) }
    func bright(_ shape: MaskShape, inverted: Bool = false) -> LocalMask {
        LocalMask(shape: shape, isInverted: inverted, adjustments: Adjustments().setting(.exposure, to: 1))
    }
    func edit(_ masks: LocalMask...) -> PhotoEdit { PhotoEdit(masks: masks) }
    /// Picture coordinates (y down from the top) to a pixel.
    func pixel(_ image: CIImage, x: Int, top: Int) throws -> Float { try PixelReader.rgb(image, x: x, y: size - 1 - top).x }
    func maxDifference(_ a: CIImage, _ b: CIImage) throws -> Float {
        var worst: Float = 0
        for x in stride(from: 0, to: size, by: 9) {
            for y in stride(from: 0, to: size, by: 9) {
                let p = try PixelReader.rgb(a, x: x, y: y), q = try PixelReader.rgb(b, x: x, y: y)
                guard p.x.isFinite, p.y.isFinite, p.z.isFinite else { return .infinity }
                worst = max(worst, abs(p.x - q.x), abs(p.y - q.y), abs(p.z - q.z))
            }
        }
        return worst
    }

    @Test func theSubjectSearchRunsAtProxySize() throws {
        let big = CIImage(color: .gray).cropped(to: CGRect(x: 0, y: 0, width: 8000, height: 6000))
        let scaled = SubjectMasker.searchImage(from: big, longSide: 2048)
        #expect(abs(scaled.extent.width - 2048) < 1); #expect(abs(scaled.extent.height - 1536) < 1)
        let small = CIImage(color: .gray).cropped(to: CGRect(x: 0, y: 0, width: 1000, height: 500))
        #expect(SubjectMasker.searchImage(from: small, longSide: 2048).extent == small.extent)
    }

    @Test func linearMaskBrightensFromStartToEnd() throws {
        let base = try grey()
        let shape = MaskShape.linear(start: MaskPoint(x: 0.5, y: 0), end: MaskPoint(x: 0.5, y: 0.5))
        let out = renderer.render(base, edit: edit(bright(shape)))
        let plain = renderer.render(base, edit: PhotoEdit())
        #expect(try pixel(out, x: 50, top: 1) - pixel(plain, x: 50, top: 1) > 0.1)
        #expect(abs(try pixel(out, x: 50, top: 98) - pixel(plain, x: 50, top: 98)) < 0.02)
    }

    @Test func radialMaskBrightensTheCentreOnly() throws {
        let base = try grey()
        let shape = MaskShape.radial(centre: MaskPoint(x: 0.5, y: 0.5), radius: 0.3, feather: 0.5)
        let out = renderer.render(base, edit: edit(bright(shape))), plain = renderer.render(base, edit: PhotoEdit())
        #expect(try pixel(out, x: 50, top: 50) - pixel(plain, x: 50, top: 50) > 0.1)
        #expect(abs(try pixel(out, x: 2, top: 2) - pixel(plain, x: 2, top: 2)) < 0.02)
    }

    @Test func radialUsesTheShorterSideOnAWideOffsetPicture() throws {
        let base = CIImage(color: CIColor(red: 0.4, green: 0.4, blue: 0.4, colorSpace: renderer.displayP3) ?? .gray)
            .cropped(to: CGRect(x: 10, y: 20, width: 200, height: 100))
        let shape = MaskShape.radial(centre: MaskPoint(x: 0.5, y: 0.5), radius: 0.4, feather: 0)
        let out = renderer.render(base, edit: edit(bright(shape))), plain = renderer.render(base, edit: PhotoEdit())
        // The centre is (110, 70) and the radius 0.4 of the 100 pt short side, 40 pt.
        #expect(try PixelReader.rgb(out, x: 145, y: 70).x - PixelReader.rgb(plain, x: 145, y: 70).x > 0.1)
        #expect(abs(try PixelReader.rgb(out, x: 155, y: 70).x - PixelReader.rgb(plain, x: 155, y: 70).x) < 0.02)
    }

    @Test func invertedRadialBrightensTheCornersOnly() throws {
        let base = try grey()
        let shape = MaskShape.radial(centre: MaskPoint(x: 0.5, y: 0.5), radius: 0.3, feather: 0.5)
        let out = renderer.render(base, edit: edit(bright(shape, inverted: true))), plain = renderer.render(base, edit: PhotoEdit())
        #expect(try pixel(out, x: 2, top: 2) - pixel(plain, x: 2, top: 2) > 0.1)
        #expect(abs(try pixel(out, x: 50, top: 50) - pixel(plain, x: 50, top: 50)) < 0.02)
    }

    @Test func brushDabBrightensWhereItWasPainted() throws {
        let base = try grey()
        let stroke = BrushStroke(dabs: [BrushDab(x: 0.25, y: 0.25, radius: 0.1)])
        let out = renderer.render(base, edit: edit(bright(.brush(strokes: [stroke])))), plain = renderer.render(base, edit: PhotoEdit())
        #expect(try pixel(out, x: 25, top: 25) - pixel(plain, x: 25, top: 25) > 0.1)
        #expect(abs(try pixel(out, x: 95, top: 95) - pixel(plain, x: 95, top: 95)) < 0.02)
        // An erasing stroke over the same dab takes the paint away again.
        let erased = [stroke, BrushStroke(dabs: stroke.dabs, isErasing: true)]
        let gone = renderer.render(base, edit: edit(bright(.brush(strokes: erased))))
        #expect(abs(try pixel(gone, x: 25, top: 25) - pixel(plain, x: 25, top: 25)) < 0.02)
    }

    @Test func degenerateMasksRenderAsIfAbsent() throws {
        let base = try grey(), plain = renderer.render(base, edit: PhotoEdit())
        let point = MaskPoint(x: 0.3, y: 0.3)
        let shapes: [MaskShape] = [
            .linear(start: point, end: point),
            .radial(centre: point, radius: 0, feather: 0.5),
            .brush(strokes: []),
            .brush(strokes: [BrushStroke(dabs: [], isErasing: false)]),
            .subject,
        ]
        for shape in shapes {
            let out = renderer.render(base, edit: edit(bright(shape)), subject: nil)
            #expect(try maxDifference(out, plain) < 1e-4, "\(shape)")
        }
    }

    @Test func aMaskWithNoAdjustmentsChangesNothing() throws {
        let base = try grey()
        let shape = MaskShape.radial(centre: MaskPoint(x: 0.5, y: 0.5), radius: 0.3, feather: 0.5)
        let out = renderer.render(base, edit: edit(LocalMask(shape: shape)))
        #expect(try maxDifference(out, renderer.render(base, edit: PhotoEdit())) < 1e-4)
    }

    @Test func renderWithAdjustmentsIsUnchanged() throws {
        let base = try grey(), adjustments = Adjustments().setting(.exposure, to: 0.5).setting(.vignette, to: -50)
        let old = renderer.render(base, adjustments: adjustments)
        let new = renderer.render(base, edit: PhotoEdit(adjustments: adjustments))
        #expect(try maxDifference(old, new) < 1e-5)
    }

    @Test func exportIncludesMasks() async throws {
        let captures = try TestFiles.directory()
        _ = try TestFiles.writeJPEG(width: 200, height: 200, rgb: SIMD3(0.4, 0.4, 0.4), to: captures.appending(path: "OC_0001.JPG"))
        let item = try #require(LibraryScanner.items(in: captures).first)
        let shape = MaskShape.linear(start: MaskPoint(x: 0.5, y: 0), end: MaskPoint(x: 0.5, y: 0.5))
        let url = try await PhotoExporter(directory: try TestFiles.directory()).export(item, edit: edit(bright(shape)))
        #expect(url.lastPathComponent == "OC_0001-edited.JPG")
        let out = try PictureDecoder.full(at: url)
        #expect(try PixelReader.rgb(out, x: 100, y: 198).x - PixelReader.rgb(out, x: 100, y: 5).x > 0.1)
    }

    @Test func exportWithASubjectMaskWritesThePhotoEvenWhenNothingIsFound() async throws {
        let captures = try TestFiles.directory()
        _ = try TestFiles.writeJPEG(width: 200, height: 200, rgb: SIMD3(0.4, 0.4, 0.4), to: captures.appending(path: "OC_0001.JPG"))
        let item = try #require(LibraryScanner.items(in: captures).first)
        let url = try await PhotoExporter(directory: try TestFiles.directory()).export(item, edit: edit(bright(.subject)))
        let out = try PictureDecoder.full(at: url)
        #expect(abs(try PixelReader.rgb(out, x: 100, y: 100).x - PixelReader.rgb(out, x: 5, y: 5).x) < 0.02)
    }

    @Test func thumbnailKeyChangesWithMasks() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let plain = ThumbnailCache.key(fileName: "a.JPG", modified: date, edit: PhotoEdit())
        let masked = ThumbnailCache.key(fileName: "a.JPG", modified: date, edit: edit(bright(.subject)))
        let moved = ThumbnailCache.key(fileName: "a.JPG", modified: date, edit: edit(LocalMask(id: UUID(), shape: .subject, adjustments: Adjustments().setting(.exposure, to: 0.5))))
        #expect(plain != masked); #expect(masked != moved)
        #expect(plain == ThumbnailCache.key(fileName: "a.JPG", modified: date, edit: PhotoEdit(masks: [])))
    }

    @Test func cubeCacheKeepsEightEntries() {
        let builds = CallCounter()
        let cache = ColourCubeCache(capacity: 8) { builds.increment(); return LookCompiler.cube(for: $0) }
        let tables = (1...9).map { Adjustments().setting(.exposure, to: Double($0) / 10) }
        for table in tables.prefix(8) { _ = cache.cube(for: table) }
        for table in tables.prefix(8) { _ = cache.cube(for: table) }
        #expect(builds.value == 8)
        _ = cache.cube(for: tables[0])   // used again, so the second entry is now the least recently used
        _ = cache.cube(for: tables[8])   // pushes that one out; a first-in-first-out cache would push out the first
        #expect(builds.value == 9)
        _ = cache.cube(for: tables[0]); #expect(builds.value == 9)   // survived
        _ = cache.cube(for: tables[1]); #expect(builds.value == 10)  // was rebuilt
    }
}
