import Foundation
import Testing
@testable import OpenCam

@MainActor @Suite struct MixerTests {
    @Test func keysTitlesAndRoundTrip() throws {
        #expect(AdjustmentKey.allCases.count == 38); #expect(EditorGroup.mix.keys.count == 24); #expect(ColourBand.red.keys == [.mixRedHue, .mixRedSaturation, .mixRedLuminance])
        #expect(AdjustmentKey.mixMagentaLuminance.title == "Magenta luminance"); #expect(AdjustmentKey.mixAquaHue.range == -100...100)
        let a = Adjustments().setting(.mixRedHue, to: 150).setting(.mixBlueLuminance, to: -30)
        #expect(a[.mixRedHue] == 100); #expect(try JSONDecoder().decode(Adjustments.self, from: JSONEncoder().encode(a)) == a)
        #expect(Adjustments().setting(.mixRedHue, to: 20).setting(.mixRedHue, to: 0) == Adjustments())
        for key in EditorGroup.mix.keys {
            let moved = Adjustments().setting(key, to: 50); #expect(key.isColour); #expect(!moved.isIdentity); #expect(moved.hasColourChanges); #expect(!moved.matches(Adjustments()))
            #expect(moved.matches(Adjustments().setting(key, to: 50.4))) } }
    @Test func stageEightRunsInsideApplyAfterSaturation() {
        let shifted = ColourMath.apply(Adjustments().setting(.mixRedHue, to: 100), to: SIMD3(0.75, 0.25, 0.25))
        #expect(abs(shifted.x - 0.75) < 1e-4); #expect(abs(shifted.y - 0.5) < 1e-4); #expect(abs(shifted.z - 0.25) < 1e-4)
        let grey = Adjustments().setting(.saturation, to: -100).setting(.mixRedSaturation, to: 100)
        let out = ColourMath.apply(grey, to: SIMD3(0.8, 0.3, 0.3)); #expect(abs(out.x - out.y) < 1e-5) }   // a grey stays grey
    @Test func stageEightWorksOnTheClampedColour() {
        let base = Adjustments().setting(.saturation, to: 50), input = SIMD3<Float>(0.2, 0.4, 0.9)
        #expect(abs(ColourMath.apply(base, to: input).y - ColourMath.apply(base.setting(.mixRedHue, to: 1), to: input).y) < 1e-3)
    }
    @Test func theMixerLanesFollowTheValues() {
        #expect(!Adjustments().hasMixerValues); #expect(Adjustments().setting(.mixBlueLuminance, to: -30).hasMixerValues)
        #expect(!Adjustments().setting(.mixBlueLuminance, to: -30).setting(.mixBlueLuminance, to: 0).hasMixerValues)
    }
    @Test func bandChoiceIsNotSaved() async throws {
        let (model, captures, looks) = try await EditorFixture.make(width: 64, height: 48); model.mixBand = .blue; model.adjustments[.mixBlueLuminance] = -30; #expect(model.save())
        guard let item = LibraryScanner.items(in: captures).first else { throw TestFileError.bitmapUnavailable }
        let reopened = EditorModel(item: item, edits: EditStore(directory: captures), looks: looks); await reopened.load()
        #expect(reopened.mixBand == .red); #expect(reopened.adjustments[.mixBlueLuminance] == -30); #expect(LookSeeder.colourStudy[.mixBlueLuminance] == -30) }
    @Test func theEncoderWritesAnAddedKeyOnlyWhenItIsNotZero() throws {
        let a = Adjustments().setting(.mixGreenHue, to: -20)
        let written = try JSONDecoder().decode([String: Double].self, from: JSONEncoder().encode(a))
        #expect(written["mixGreenHue"] == -20); #expect(written["mixRedHue"] == nil); #expect(written.count == 15)
    }
}
