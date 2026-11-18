import Foundation
import Testing
@testable import OpenCam

@Suite struct RawSizeCheckTests {
    static let small = RawSizeCheckSize(width: 4032, height: 3024)
    static let large = RawSizeCheckSize(width: 8064, height: 6048)

    static func format(_ sizes: [RawSizeCheckSize]) -> RawSizeCheckFormatFacts {
        RawSizeCheckFormatFacts(width: 4032, height: 3024, mediaSubType: "420f", supportedMaxPhotoDimensions: sizes,
                                isHighestPhotoQualitySupported: true, maxFramesPerSecond: 30)
    }

    static func trial(_ route: RawSizeCheckRoute, camera: String = "wide", rawSize: RawSizeCheckSize?, skipReason: String? = nil) -> RawSizeCheckTrial {
        var trial = RawSizeCheckTrial(route: route, camera: camera, deviceType: "type", format: format([small, large]),
                                      sessionPreset: "AVCaptureSessionPresetPhoto", requestedMaxPhotoDimensions: large, skipReason: skipReason)
        if let rawSize {
            trial.capture = RawSizeCheckCapture(kind: .bayerRAW, rawPixelFormat: "bgg4", requestedMaxPhotoDimensions: large,
                                                resolvedRawPhotoDimensions: rawSize, resolvedPhotoDimensions: rawSize,
                                                photos: [RawSizeCheckPhoto(isRaw: true, size: rawSize, imageSizes: [rawSize], bytes: 1)],
                                                milliseconds: 900, isTimedOut: false, error: nil)
        }
        return trial
    }

    @Test func noTrialsMeansNoRaw() {
        let summary = RawSizeCheckSummary.make(from: [])
        #expect(summary.largestRawSize == nil)
        #expect(summary.sentence == "No trial delivered a RAW photo.")
    }

    @Test func skippedTrialsDeliverNothing() {
        let summary = RawSizeCheckSummary.make(from: [Self.trial(.photoPreset, rawSize: nil, skipReason: "no Bayer")])
        #expect(summary.largestRawSize == nil)
        #expect(summary.skippedCount == 1)
        #expect(summary.trialCount == 1)
    }

    @Test func nothingAboveTwelveMegapixelsSaysSo() {
        let summary = RawSizeCheckSummary.make(from: [Self.trial(.photoPreset, rawSize: Self.small), Self.trial(.chosenFormat, rawSize: Self.small)])
        #expect(summary.largestRawSize == Self.small)
        #expect(summary.sentence == "No route delivered a RAW larger than 4032 x 3024.")
        #expect(summary.rawDeliveredCount == 2)
    }

    @Test func aLargerRawNamesRouteCameraAndFormat() {
        let trials = [Self.trial(.photoPreset, rawSize: Self.small), Self.trial(.chosenFormat, camera: "ultra wide", rawSize: Self.large)]
        let summary = RawSizeCheckSummary.make(from: trials)
        #expect(summary.largestRawSize == Self.large)
        #expect(summary.route == .chosenFormat)
        #expect(summary.camera == "ultra wide")
        #expect(summary.sentence.hasPrefix("Route C on the ultra wide camera delivered 8064 x 6048 with format 4032x3024 420f"))
    }

    @Test func theFirstTrialWinsATie() {
        let trials = [Self.trial(.proRAW, rawSize: Self.large), Self.trial(.chosenFormat, rawSize: Self.large)]
        #expect(RawSizeCheckSummary.make(from: trials).route == .proRAW)
    }

    @Test func aProcessedPhotoIsNotARaw() {
        var trial = Self.trial(.rawWithCompanion, rawSize: Self.small)
        trial.capture?.photos.append(RawSizeCheckPhoto(isRaw: false, size: Self.large, imageSizes: [Self.large], bytes: 1))
        #expect(RawSizeCheckSummary.make(from: [trial]).largestRawSize == Self.small)
    }

    @Test func theReportEncodesTheSummaryAndTrialsAndReadsBack() throws {
        var report = RawSizeCheckReport(takenAt: Date(timeIntervalSince1970: 0), modelIdentifier: "iPhone19,4", osVersion: "Version 27.1",
                                        osBuild: "24A1", buildConfiguration: "Release", notes: ["note"])
        report.trials = [Self.trial(.photoPreset, rawSize: Self.large)]
        report.refreshSummary()
        let data = try RawSizeCheckStore.encode(report)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let summary = try #require(object["summary"] as? [String: Any])
        #expect(summary["sentence"] as? String != nil)
        #expect((object["trials"] as? [Any])?.count == 1)
        #expect(object["takenAt"] as? String == "1970-01-01T00:00:00Z")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        #expect(try decoder.decode(RawSizeCheckReport.self, from: data) == report)
    }

    @Test func theLaunchArgumentParsesWithoutScriptingTheLaunch() {
        let config = LaunchConfig.parse(["OpenCam", "-rawSizeCheck"])
        #expect(config.runsRawSizeCheck)
        #expect(!config.isScripted)
        #expect(!LaunchConfig.parse([]).runsRawSizeCheck)
    }

    @Test func fourCharacterCodesReadAsText() {
        #expect(RawSizeCheckFourCC.string(0x6267_6734) == "bgg4")
        #expect(RawSizeCheckFourCC.string(7) == "7")
    }
}
