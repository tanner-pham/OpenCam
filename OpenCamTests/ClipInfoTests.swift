import Foundation
import Testing
@testable import OpenCam

@Suite struct ClipInfoTests {
    private static let proRes = VideoCodec(family: .proRes, quality: "422 HQ", codecType: "apch", bitrateTier: nil)

    private static func facts(colour: ColourMode? = .hlg, dropped: Int? = 0) -> ClipFacts {
        ClipFacts(codecFourCC: "apch", width: 3840, height: 2160, nominalFrameRate: 29.97, durationSeconds: 60, frameCount: 1798,
                  droppedFrames: dropped, colour: colour, megabitsPerSecond: 148.2, hasAudio: true)
    }

    private static func sidecar(actual: ClipFacts?, drops: DropFacts? = nil) -> ClipSidecar {
        let requested = VideoOption(lensID: "back", codec: proRes, resolution: Resolution.named(width: 3840, height: 2160), frameRate: 30, colour: .rec709)
        return ClipSidecar(requested: requested, actual: actual, outcome: "recorded", recordedAt: Date(timeIntervalSince1970: 0), error: nil,
                           recorder: .writer, drops: drops)
    }

    @Test func aWriterClipListsEveryFact() {
        let info = ClipInfo(sidecar: Self.sidecar(actual: Self.facts(), drops: DropFacts(total: 3)))
        #expect(info.rows.map(\.title) == ["Codec", "Size", "Frame rate", "Colour", "Data rate", "Duration", "Sound", "Dropped frames"])
        #expect(info.rows.map(\.value) == ["ProRes 422 HQ", "4K, 3840 × 2160", "29.97 fps", "HLG", "148 Mb/s", "1:00", "Yes", "3"])
        #expect(info.summary == "ProRes 422 HQ · 4K · 29.97 fps · HLG")
    }

    @Test func aSystemClipTakesDroppedFramesFromTheFile() {
        let info = ClipInfo(sidecar: Self.sidecar(actual: Self.facts(dropped: 0)))
        #expect(info.rows.last == PhotoInfoRow(title: "Dropped frames", value: "None"))
        #expect(ClipInfo(sidecar: Self.sidecar(actual: Self.facts(dropped: nil))).rows.contains { $0.title == "Dropped frames" } == false)
    }

    @Test func aClipThatWasNotReadBackShowsWhatWasAsked() {
        let info = ClipInfo(sidecar: Self.sidecar(actual: nil))
        #expect(info.rows.map(\.title) == ["Codec", "Size", "Frame rate", "Colour"])
        #expect(info.rows.map(\.value) == ["ProRes 422 HQ", "4K, 3840 × 2160", "30 fps", "Rec. 709"])
    }

    @Test func aMissingOrUnreadableSidecarSaysSo() async throws {
        let none = ClipInfo(sidecar: nil)
        #expect(none.summary == LibraryCopy.noClipDetails); #expect(none.rows.isEmpty)
        let dir = try TestFiles.directory()
        let clip = dir.appending(path: "OC_0001.MOV"), sidecar = dir.appending(path: "OC_0001.json")
        try Data("x".utf8).write(to: clip); try Data("{".utf8).write(to: sidecar)
        let item = LibraryItem(kind: .clip, stem: "OC_0001", pictureURL: clip, rawURL: nil, sidecarURL: sidecar, modified: .now)
        #expect(await ClipInfo.load(for: item) == none)
        let bare = LibraryItem(kind: .clip, stem: "OC_0001", pictureURL: clip, rawURL: nil, sidecarURL: nil, modified: .now)
        #expect(await ClipInfo.load(for: bare) == none)
    }

    @Test func frameRateAndDataRateText() {
        #expect(ClipInfo.frameRateText(30) == "30 fps"); #expect(ClipInfo.frameRateText(29.97) == "29.97 fps")
        #expect(ClipInfo.frameRateText(59.94006) == "59.94 fps")
        #expect(ClipInfo.dataRateText(megabitsPerSecond: 148.2) == "148 Mb/s"); #expect(ClipInfo.dataRateText(megabitsPerSecond: 10) == "10 Mb/s")
        #expect(ClipInfo.dataRateText(megabitsPerSecond: 6.24) == "6.2 Mb/s")
    }

    @Test func noStringHasAnEmDash() {
        let info = ClipInfo(sidecar: Self.sidecar(actual: Self.facts(), drops: DropFacts(total: 3)))
        let strings = [info.summary, LibraryCopy.noClipDetails, LibraryCopy.clipInfoTitle, LibraryCopy.deleteClipTitle, LibraryCopy.deleteClipMessage]
            + info.rows.flatMap { [$0.title, $0.value] }
        #expect(strings.allSatisfy { !$0.contains("\u{2014}") })
    }
}
