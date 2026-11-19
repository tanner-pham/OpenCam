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

    @Test func aFailedWriteLeavesNoClipAndNoSidecarBehind() async throws {
        let dir = try TestFiles.directory(); let captures = try CaptureStore(directory: dir)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: dir.path(percentEncoded: false))
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path(percentEncoded: false)) }
        await #expect(throws: LibraryError.self) { try await SampleSeeder.seedClipIfAbsent(captures) }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path(percentEncoded: false))
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path(percentEncoded: false)).isEmpty)
    }
}
