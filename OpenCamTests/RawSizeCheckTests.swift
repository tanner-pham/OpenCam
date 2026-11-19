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

    static func trial(_ route: RawSizeCheckRoute, camera: String = "wide", rawSize: RawSizeCheckSize?, skipReason: String? = nil,
                      outcome: RawSizeCheckOutcome = .ran) -> RawSizeCheckTrial {
        var trial = RawSizeCheckTrial(route: route, camera: camera, deviceType: "type", format: format([small, large]),
                                      sessionPreset: "AVCaptureSessionPresetPhoto", requestedMaxPhotoDimensions: large,
                                      outcome: outcome, skipReason: skipReason)
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
        #expect(summary.sentence.hasPrefix("No trial delivered a RAW photo. 0 trials ran,"))
    }

    @Test func skippedTrialsDeliverNothing() {
        let summary = RawSizeCheckSummary.make(from: [Self.trial(.photoPreset, rawSize: nil, skipReason: "no Bayer", outcome: .refused)])
        #expect(summary.largestRawSize == nil)
        #expect(summary.refusedCount == 1)
        #expect(summary.trialCount == 1)
    }

    @Test func nothingAboveTwelveMegapixelsSaysSo() {
        let summary = RawSizeCheckSummary.make(from: [Self.trial(.photoPreset, rawSize: Self.small), Self.trial(.chosenFormat, rawSize: Self.small)])
        #expect(summary.largestRawSize == Self.small)
        #expect(summary.sentence.hasPrefix("No route delivered a RAW larger than 4032 x 3024. 2 trials ran,"))
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

    @Test func anUnreadableDNGCountsWithTheResolvedSize() {
        var trial = Self.trial(.chosenFormat, rawSize: Self.large)
        trial.capture?.photos = [RawSizeCheckPhoto(isRaw: true, size: nil, imageSizes: [], bytes: 1)]
        let summary = RawSizeCheckSummary.make(from: [trial])
        #expect(summary.largestRawSize == Self.large)
        #expect(summary.sentence.contains("(DNG data: unreadable; resolved settings: 8064 x 6048)"))
    }

    @Test func aDisagreementBetweenFileAndSettingsIsSaid() {
        var trial = Self.trial(.photoPreset, rawSize: Self.small)
        trial.capture?.resolvedRawPhotoDimensions = Self.large
        let summary = RawSizeCheckSummary.make(from: [trial])
        #expect(summary.largestRawSize == Self.small)
        #expect(summary.sentence.contains("(DNG data: 4032 x 3024; resolved settings: 8064 x 6048)"))
    }

    @Test func aTimedOutCaptureDeliversNothingEvenWithResolvedSizes() {
        var trial = Self.trial(.photoPreset, rawSize: Self.large)
        trial.capture?.photos = []
        trial.capture?.isTimedOut = true
        #expect(RawSizeCheckSummary.make(from: [trial]).largestRawSize == nil)
    }

    @Test func outcomesAreCountedAndNamedInTheSentence() {
        let trials = [Self.trial(.photoPreset, rawSize: Self.small), Self.trial(.proRAW, rawSize: nil, skipReason: "x", outcome: .refused),
                      Self.trial(.chosenFormat, rawSize: nil, skipReason: "y", outcome: .unsafe),
                      Self.trial(.chosenFormat, rawSize: nil, skipReason: "z", outcome: .budget),
                      Self.trial(.chosenFormat, rawSize: nil, skipReason: "z", outcome: .budget)]
        let summary = RawSizeCheckSummary.make(from: trials)
        #expect((summary.ranCount, summary.refusedCount, summary.unsafeCount, summary.budgetCount) == (1, 1, 1, 2))
        #expect(summary.sentence == "No route delivered a RAW larger than 4032 x 3024. 1 trials ran, 1 were refused by the phone, 1 were held back as unsafe, 2 were cut by the time budget.")
    }

    @Test func routesAToBRunOnEveryCameraBeforeRouteC() {
        let plan = RawSizeCheckStep.plan(cameraCount: 3)
        #expect(plan.map(\.phase) == [.photoPreset, .photoPreset, .photoPreset, .chosenFormats, .chosenFormats, .chosenFormats])
        #expect(plan.map(\.cameraIndex) == [0, 1, 2, 0, 1, 2])
        #expect(RawSizeCheckStep.plan(cameraCount: 0).isEmpty)
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
