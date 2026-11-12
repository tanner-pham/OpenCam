import CoreImage
import CoreVideo
import Foundation
import Testing
@testable import OpenCam

/// The baked Log render on synthetic buffers: 64 x 64 `x420` frames filled with one colour, tagged HLG BT.2020. Ten-bit values sit
/// in the high bits of each 16-bit sample. There is no camera in the Simulator, so what these tests cannot show is how the render
/// behaves on real frames at 4K and 30 or 60 fps, its time, and how a player reads the tags; those are on the device checklist.
@Suite struct RecordingRenderTests {
    enum Failure: Error {
        case pixelBuffer(CVReturn)
        case readback
    }

    static func makeRender() -> RecordingRender { RecordingRender(cube: LogProfile.bakeCube()) }

    /// A frame with luma `y` and chroma `cb`, `cr` as ten-bit codes.
    static func frame(y: UInt16, cb: UInt16 = 512, cr: UInt16 = 512, size: Int = 64) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let made = CVPixelBufferCreate(kCFAllocatorDefault, size, size, kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
                                       [kCVPixelBufferIOSurfacePropertiesKey: [:], kCVPixelBufferMetalCompatibilityKey: true] as CFDictionary, &buffer)
        guard made == kCVReturnSuccess, let buffer else { throw Failure.pixelBuffer(made) }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        for plane in 0..<2 {
            guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, plane) else { throw Failure.readback }
            let width = CVPixelBufferGetWidthOfPlane(buffer, plane), height = CVPixelBufferGetHeightOfPlane(buffer, plane)
            let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(buffer, plane)
            for row in 0..<height {
                let samples = base.advanced(by: row * rowBytes).assumingMemoryBound(to: UInt16.self)
                for column in 0..<width {
                    if plane == 0 {
                        samples[column] = y << 6
                    } else {
                        samples[column * 2] = cb << 6
                        samples[column * 2 + 1] = cr << 6
                    }
                }
            }
        }
        CVBufferSetAttachment(buffer, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_2020, .shouldPropagate)
        CVBufferSetAttachment(buffer, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_2100_HLG, .shouldPropagate)
        CVBufferSetAttachment(buffer, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_2020, .shouldPropagate)
        return buffer
    }

    /// The ten-bit code at the middle of each plane: luma, then Cb and Cr.
    static func centre(of buffer: CVPixelBuffer) throws -> (y: Int, cb: Int, cr: Int) {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let luma = CVPixelBufferGetBaseAddressOfPlane(buffer, 0), let chroma = CVPixelBufferGetBaseAddressOfPlane(buffer, 1) else { throw Failure.readback }
        let lumaRow = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0), chromaRow = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1)
        let y = luma.advanced(by: 32 * lumaRow).assumingMemoryBound(to: UInt16.self)[32] >> 6
        let pair = chroma.advanced(by: 16 * chromaRow).assumingMemoryBound(to: UInt16.self)
        return (Int(y), Int(pair[32] >> 6), Int(pair[33] >> 6))
    }

    static func attachment(_ key: CFString, of buffer: CVPixelBuffer) -> String? {
        CVBufferCopyAttachment(buffer, key, nil) as? String
    }

    @Test func aGreyFrameComesOutAtTheCurveValue() throws {
        let out = try #require(Self.makeRender().render(try Self.frame(y: 397)))
        let code = try Self.centre(of: out)
        #expect(abs(code.y - 458) <= 3, "luma \(code.y)")
    }

    @Test func blackIsLiftedAndPeakWhiteIsKept() throws {
        let render = Self.makeRender()
        let black = try Self.centre(of: try #require(render.render(try Self.frame(y: 64))))
        let white = try Self.centre(of: try #require(render.render(try Self.frame(y: 940))))
        #expect(abs(black.y - 123) <= 3, "black \(black.y)")
        #expect(abs(white.y - 797) <= 3, "white \(white.y)")
    }

    @Test func neutralStaysNeutral() throws {
        let code = try Self.centre(of: try #require(Self.makeRender().render(try Self.frame(y: 397))))
        #expect(abs(code.cb - 512) <= 3, "cb \(code.cb)")
        #expect(abs(code.cr - 512) <= 3, "cr \(code.cr)")
    }

    @Test func theOutputIsTaggedBT2020WithTheRec709Curve() throws {
        let out = try #require(Self.makeRender().render(try Self.frame(y: 397)))
        #expect(Self.attachment(kCVImageBufferColorPrimariesKey, of: out) == kCVImageBufferColorPrimaries_ITU_R_2020 as String)
        #expect(Self.attachment(kCVImageBufferTransferFunctionKey, of: out) == kCVImageBufferTransferFunction_ITU_R_709_2 as String)
        #expect(Self.attachment(kCVImageBufferYCbCrMatrixKey, of: out) == kCVImageBufferYCbCrMatrix_ITU_R_2020 as String)
        #expect(CVPixelBufferGetPixelFormatType(out) == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange)
        #expect(CVPixelBufferGetWidth(out) == 64 && CVPixelBufferGetHeight(out) == 64)
    }

    @Test func theSourceIsNotChanged() throws {
        let source = try Self.frame(y: 397)
        let out = try #require(Self.makeRender().render(source))
        #expect(out !== source)
        let code = try Self.centre(of: source)
        #expect(code.y == 397 && code.cb == 512 && code.cr == 512)
        #expect(Self.attachment(kCVImageBufferTransferFunctionKey, of: source) == kCVImageBufferTransferFunction_ITU_R_2100_HLG as String)
    }

    @Test func aHeldPoolReturnsNil() throws {
        let render = Self.makeRender()
        var held: [CVPixelBuffer] = []
        for _ in 0..<6 { held.append(try #require(render.render(try Self.frame(y: 397)))) }
        #expect(render.render(try Self.frame(y: 397)) == nil)
        // A buffer given back makes room again.
        held.removeFirst()
        #expect(render.render(try Self.frame(y: 397)) != nil)
    }

    @Test func aPoolThatCannotBeMadeFailsThePreparation() {
        #expect(!Self.makeRender().prepare(width: 0, height: 0))
        #expect(Self.makeRender().prepare(width: 64, height: 64))
    }
}
