import Testing
@testable import OpenCam

/// The lines the format summary is drawn in: one, the format and the look, or one part per line.
@Suite struct SummaryFormTests {
    let withLook = ["HEVC", "4K", "Rec. 709", "Warm fade"]
    let noLook = ["HEVC", "4K", "Rec. 709"]

    @Test func oneLineJoinsEveryPartWithTwoSpaces() {
        #expect(SummaryForm.oneLine.lines(parts: withLook, hasLook: true) == ["HEVC  4K  Rec. 709  Warm fade"])
        #expect(SummaryForm.oneLine.lines(parts: noLook, hasLook: false) == ["HEVC  4K  Rec. 709"])
    }

    @Test func theMiddleFormPutsTheLookOnASecondLine() {
        #expect(SummaryForm.formatAndLook.lines(parts: withLook, hasLook: true) == ["HEVC  4K  Rec. 709", "Warm fade"])
        // Without a look there is nothing to put on a second line.
        #expect(SummaryForm.formatAndLook.lines(parts: noLook, hasLook: false) == ["HEVC  4K  Rec. 709"])
    }

    @Test func theLastResortIsOnePartPerLine() {
        #expect(SummaryForm.onePerLine.lines(parts: withLook, hasLook: true) == withLook)
        #expect(SummaryForm.onePerLine.lines(parts: ["RAW + HEIF", "48 MP"], hasLook: false) == ["RAW + HEIF", "48 MP"])
    }

    @Test func noCameraIsOneDashInEveryForm() {
        for form in [SummaryForm.oneLine, .formatAndLook, .onePerLine] {
            #expect(form.lines(parts: ["--"], hasLook: false) == ["--"])
        }
    }

    @Test func aLookWithNothingElseStaysAlone() {
        #expect(SummaryForm.formatAndLook.lines(parts: ["Warm fade"], hasLook: true) == ["Warm fade"])
    }
}
