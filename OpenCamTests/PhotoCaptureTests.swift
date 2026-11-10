import CoreVideo
import Foundation
import Testing
@testable import OpenCam

@MainActor @Suite struct PhotoCaptureTests {   // CaptureStore is main-actor
    let bayer = kCVPixelFormatType_14Bayer_BGGR
    @Test func namesAndSequence() {
        #expect(CaptureStore.fileName(sequence: 1, kind: .dng) == "OC_0001.DNG"); #expect(CaptureStore.fileName(sequence: 12345, kind: .mov) == "OC_12345.MOV")
        #expect(CaptureStore.nextSequence(existingNames: ["OC_0001.DNG", "OC_0001.HEIC", "OC_0002.MOV", "OC_0002.json", "sweep-2026-11-09-143005.json", "notes.txt"]) == 3)
        #expect(CaptureStore.nextSequence(existingNames: []) == 1)
    }
    @Test func rawRules() {
        #expect(throws: PhotoCaptureError.rawNeedsUnitZoom(zoom: 2)) { try PhotoSettingsPlan.make(format: .raw, availableRawFormats: [bayer], isBayer: { $0 == bayer }, zoomFactor: 2) }
        #expect(throws: PhotoCaptureError.rawUnavailable) { try PhotoSettingsPlan.make(format: .rawPlusHEIF, availableRawFormats: [], isBayer: { _ in false }, zoomFactor: 1) }
    }
    @Test func plans() throws {
        #expect(try PhotoSettingsPlan.make(format: .rawPlusHEIF, availableRawFormats: [bayer], isBayer: { $0 == bayer }, zoomFactor: 1)
                == PhotoSettingsPlan(rawPixelFormat: bayer, wantsProcessedHEIF: true, prioritizesSpeed: true))
        #expect(try PhotoSettingsPlan.make(format: .heif, availableRawFormats: [bayer], isBayer: { $0 == bayer }, zoomFactor: 2)
                == PhotoSettingsPlan(rawPixelFormat: nil, wantsProcessedHEIF: true, prioritizesSpeed: false))
    }
}
