import AVFoundation
import Foundation
import Testing
@testable import OpenCam

@MainActor @Suite struct SampleClipSeederTests {
    @Test func seedsOnePlayableClipWithItsSidecar() async throws {
        let dir = try TestFiles.directory(); let captures = try CaptureStore(directory: dir)
        #expect(try await SampleSeeder.seedClipIfAbsent(captures) == 1)
        let items = LibraryScanner.items(in: dir)
        #expect(items.count == 1)
        let item = try #require(items.first); let sidecarURL = try #require(item.sidecarURL)
        #expect(item.kind == .clip)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let sidecar = try decoder.decode(ClipSidecar.self, from: Data(contentsOf: sidecarURL))
        let actual = try #require(sidecar.actual)
        #expect(actual.codecFourCC == "avc1"); #expect(actual.width == 1280); #expect(actual.height == 720)
        #expect(actual.nominalFrameRate == 30); #expect(abs(actual.durationSeconds - 3) <= 0.1); #expect(actual.colour == .rec709)
        #expect(!actual.hasAudio)
        #expect(try await AVURLAsset(url: item.pictureURL).load(.isPlayable))
    }

    @Test func seedsNothingWhenAClipExists() async throws {
        let dir = try TestFiles.directory(); let captures = try CaptureStore(directory: dir)
        #expect(try await SampleSeeder.seedClipIfAbsent(captures) == 1)
        #expect(try await SampleSeeder.seedClipIfAbsent(captures) == 0)
        #expect(LibraryScanner.items(in: dir).count == 1)
    }
}
