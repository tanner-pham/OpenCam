import CoreGraphics
import Foundation
import Testing
@testable import OpenCam

actor HistogramGate {   // holds every histogram until opened
    private var isOpen = false, waiting: [CheckedContinuation<Void, Never>] = []
    func pass() async { if !isOpen { await withCheckedContinuation { waiting.append($0) } } }
    func open() { isOpen = true; waiting.forEach { $0.resume() }; waiting = [] } }
@MainActor @Suite struct EditorHistogramTests {
    @Test func countsChannelsAndLuma() {
        let h = PictureHistogram.counting(rgba: [255, 0, 0, 255, 0, 0, 0, 255, 128, 128, 128, 0])
        #expect(h.red[255] == 1); #expect(h.red[0] == 1); #expect(h.red[128] == 1); #expect(h.green[0] == 2)
        #expect(h.luma[54] == 1); #expect(h.luma[0] == 1); #expect(h.luma[128] == 1); #expect(h.luma.reduce(0, +) == 3)
        #expect(h.heights(.red)[255] == 1); #expect(h.heights(.red)[128] == 1)          // the peak ignores bins 0 and 255
    }
    @Test func histogramOfAGreyProxyPeaksAtItsGrey() async throws {
        let (model, _, _) = try await EditorFixture.make(width: 640, height: 480); await model.waitForHistogram(); let h = try #require(model.histogram)
        #expect(h.luma.reduce(0, +) == 256 * 192); #expect((126...130).contains(h.luma.firstIndex { $0 > 0 } ?? 0)) }
    @Test func aHeldHistogramNeverDelaysThePreview() async throws {   // Review Focus 5
        let captures = try TestFiles.directory(), gate = HistogramGate()
        _ = try TestFiles.writeJPEG(width: 640, height: 480, rgb: SIMD3(0.5, 0.5, 0.5), to: captures.appending(path: "OC_0001.JPG"))
        guard let item = LibraryScanner.items(in: captures).first else { throw TestFileError.bitmapUnavailable }
        let model = EditorModel(item: item, edits: EditStore(directory: captures), looks: try LookStore(directory: TestFiles.directory()),
                                makeHistogram: { image in await gate.pass(); return await PictureHistogram.make(from: image) })
        await model.load(); #expect(model.phase == .ready); #expect(model.histogram == nil)
        for v in stride(from: 10.0, through: 60, by: 10) { model.adjustments[.contrast] = v; await model.waitForPreview() }
        #expect(model.renderedAdjustments?[.contrast] == 60); #expect(model.previewRenderCount == 7); #expect(model.histogram == nil); await gate.open(); await model.waitForHistogram()
        #expect(model.histogram != nil) } }
