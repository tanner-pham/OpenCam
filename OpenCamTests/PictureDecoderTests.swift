import CoreImage
import Foundation
import Testing
@testable import OpenCam

@Suite struct PictureDecoderTests {
    @Test func proxyIsCappedAndNeverUpscaled() async throws {
        let dir = try TestFiles.directory()
        let wide = try TestFiles.writeJPEG(width: 3000, height: 1500, rgb: SIMD3(0.5, 0.5, 0.5), to: dir.appending(path: "wide.JPG"))
        let small = try TestFiles.writeJPEG(width: 100, height: 50, rgb: SIMD3(0.5, 0.5, 0.5), to: dir.appending(path: "small.JPG"))
        #expect(try await PictureDecoder.proxy(at: wide, longSide: 2048).extent.size == CGSize(width: 2048, height: 1024))
        #expect(try await PictureDecoder.proxy(at: small, longSide: 2048).extent.size == CGSize(width: 100, height: 50))
        #expect(try PictureDecoder.pixelSize(at: wide) == CGSize(width: 3000, height: 1500))
    }
    @Test func missingAndUndecodableFilesThrow() async throws {
        let dir = try TestFiles.directory(), junk = dir.appending(path: "junk.JPG"), gone = dir.appending(path: "gone.JPG")
        try Data("not a picture".utf8).write(to: junk)
        await #expect(throws: PictureError.undecodable(path: junk.path(percentEncoded: false))) { try await PictureDecoder.proxy(at: junk, longSide: 360) }
        await #expect(throws: PictureError.missing(path: gone.path(percentEncoded: false))) { try await PictureDecoder.proxy(at: gone, longSide: 360) }
        #expect(throws: PictureError.self) { try PictureDecoder.full(at: junk) }
    }
    @Test func heicHelperRoundTripsInTheSimulator() throws {   // Task 9's HEIF test depends on HEIC encoding in OpenCam Dev
        let url = try TestFiles.writeHEIC(width: 64, height: 48, rgb: SIMD3(0.4, 0.5, 0.6), to: TestFiles.directory().appending(path: "probe.HEIC"))
        #expect(try PictureDecoder.pixelSize(at: url) == CGSize(width: 64, height: 48))
        #expect(diff(try PixelReader.rgb(PictureDecoder.full(at: url), x: 32, y: 24), SIMD3(0.4, 0.5, 0.6)) < 0.03)
    }
    func diff(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float { ((a - b) * (a - b)).squareRoot().max() }
}
