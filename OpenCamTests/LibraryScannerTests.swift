import Foundation
import Testing
@testable import OpenCam

@Suite struct LibraryScannerTests {
    let dir = URL(filePath: "/tmp/Captures", directoryHint: .isDirectory)
    @Test func pairsDNGWithHEICListsClipsAndOrdersNewestFirst() throws {
        let items = LibraryScanner.group(names: ["OC_0001.DNG", "OC_0001.HEIC", "OC_0001.edit.json", "OC_0002.MOV", "OC_0002.json", "OC_0003.DNG", "OC_0006.MOV",
                                                 "OC_0010.jpg", "OC_0004.PNG", "IMG_7.jpeg", "notes.txt", "sweep-2026-11-09-143005.json", "OC_0005.HEIF",
                                                 "OC_0011.json"], directory: dir)   // OC_0011.json: a sweep clip's sidecar, clip deleted
        #expect(items.map(\.id) == ["OC_0010", "OC_0006.MOV", "OC_0005", "OC_0004", "OC_0003", "OC_0002.MOV", "OC_0001", "IMG_7"])
        #expect(items.map(\.kind) == [.photo, .clip, .photo, .photo, .photo, .clip, .photo, .photo])
        let paired = try #require(items.first { $0.id == "OC_0001" })
        #expect(paired.pictureURL.lastPathComponent == "OC_0001.HEIC"); #expect(paired.rawURL?.lastPathComponent == "OC_0001.DNG"); #expect(paired.fileURLs.count == 2)
        let rawOnly = try #require(items.first { $0.id == "OC_0003" })
        #expect(rawOnly.pictureURL.lastPathComponent == "OC_0003.DNG"); #expect(rawOnly.fileURLs.count == 1); #expect(rawOnly.isEditable)
        let clip = try #require(items.first { $0.id == "OC_0002.MOV" })
        #expect(!clip.isEditable); #expect(clip.rawURL == nil); #expect(clip.fileURLs.map(\.lastPathComponent) == ["OC_0002.MOV", "OC_0002.json"])
        #expect(items.first { $0.id == "OC_0006.MOV" }?.sidecarURL == nil)
        #expect(LibraryScanner.sequence(ofStem: "OC_12345") == 12345); #expect(LibraryScanner.sequence(ofStem: "IMG_7") == nil); #expect(LibraryScanner.sequence(ofStem: "OC_") == nil)
    }
    @Test func clipDurationComesFromTheSidecar() async throws {
        let dir = try TestFiles.directory()
        try Data("x".utf8).write(to: dir.appending(path: "OC_0002.MOV")); try Data("x".utf8).write(to: dir.appending(path: "OC_0003.MOV"))
        let option = VideoOption(lensID: "wide", codec: VideoCodec(family: .hevc, quality: "High", codecType: "hvc1", bitrateTier: .high), resolution: .named(width: 3840, height: 2160), frameRate: 30, colour: .rec709)
        let facts = ClipFacts(codecFourCC: "hvc1", width: 3840, height: 2160, nominalFrameRate: 30, durationSeconds: 42.5, frameCount: 1275, droppedFrames: 0, colour: .rec709, megabitsPerSecond: 44, hasAudio: true)
        try ClipSidecar(requested: option, actual: facts, outcome: "complete", recordedAt: .now, error: nil).encoded().write(to: dir.appending(path: "OC_0002.json"))
        let items = LibraryScanner.items(in: dir)
        #expect(await ClipDuration.seconds(of: try #require(items.first { $0.id == "OC_0002.MOV" })) == 42.5)
        #expect(await ClipDuration.seconds(of: try #require(items.first { $0.id == "OC_0003.MOV" })) == nil)   // no sidecar, unreadable file
    }
}
