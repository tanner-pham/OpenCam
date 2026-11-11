import Foundation
import Testing
@testable import OpenCam

/// The indexed record resolver and the model's cached resolvers must answer exactly as the resolvers did before, on the
/// phone's real list: every lens, a broad sample of selections (the lens's own, other lenses', and values no lens has).
@MainActor @Suite struct ResolverEquivalenceTests {
    /// Selections drawn from every lens's options, plus variants with values no option has.
    private static func sampleSelections(_ capabilities: CaptureCapabilities) -> [RecordSelection] {
        let drawn = stride(from: 0, to: capabilities.videoOptions.count, by: 31).map { index in
            let option = capabilities.videoOptions[index]
            return RecordSelection(family: option.codec.family, quality: option.codec.quality, resolution: option.resolution,
                                   frameRate: option.frameRate, colour: option.colour)
        }
        let varied = drawn.enumerated().compactMap { index, selection -> RecordSelection? in
            var changed = selection
            switch index % 5 {
            case 0: changed.frameRate = 59
            case 1: changed.quality = "422 HQ"
            case 2: changed.resolution = .named(width: 5000, height: 3000)
            case 3: changed.family = .proRes
            default: changed.colour = .appleLog2
            }
            return changed
        }
        return drawn + varied
    }

    @Test func indexedRecordResolverMatchesTheReference() throws {
        let capabilities = try Fixture.loadDuo()
        let selections = Self.sampleSelections(capabilities)
        var compared = 0
        for lens in capabilities.lenses + [nil] {
            let new = RecordSelectionResolver(options: capabilities.videoOptions, lens: lens)
            let old = ReferenceRecordSelectionResolver(options: capabilities.videoOptions, lens: lens)
            #expect(new.defaultSelection() == old.defaultSelection())
            for (index, selection) in selections.enumerated() {
                #expect(new.option(for: selection) == old.option(for: selection))
                #expect(new.settled(selection) == old.settled(selection))
                for row in RecordRow.allCases {
                    let chips = new.chips(row, for: selection)
                    #expect(chips == old.chips(row, for: selection))
                    #expect(new.reasonLine(row, for: selection) == old.reasonLine(row, for: selection))
                    // Every chip of the row, chosen, on an eighth of the sample.
                    guard index % 8 == 0 else { continue }
                    for chip in chips {
                        #expect(new.select(row, chipID: chip.id, in: selection) == old.select(row, chipID: chip.id, in: selection))
                    }
                    #expect(new.select(row, chipID: "none", in: selection) == old.select(row, chipID: "none", in: selection))
                }
                compared += 1
            }
        }
        #expect(compared > 1_000)
    }

    @Test func modelResolversMatchTheReferenceOnEveryLens() throws {
        let capabilities = try Fixture.loadDuo()
        let model = CameraModel(config: LaunchConfig(), capabilities: capabilities, isSimulator: true, defaults: try Fixture.freshDefaults())
        let photoSelections = PhotoFormat.allCases.flatMap { format in [0, 12, 24, 48, 200].map { PhotoSelection(format: format, megapixels: $0) } }
        for lens in capabilities.lenses {
            model.selectLens(lens.id)
            let old = ReferenceRecordSelectionResolver(options: capabilities.videoOptions, lens: lens)
            #expect(model.record == old.settled(model.record))
            #expect(model.currentVideoOption == old.option(for: model.record))
            for row in RecordRow.allCases {
                #expect(model.recordResolver.chips(row, for: model.record) == old.chips(row, for: model.record))
            }
            let oldPhoto = ReferencePhotoSelectionResolver(options: capabilities.photoOptions, lenses: capabilities.lenses, lensID: lens.id)
            #expect(model.currentPhotoOption == oldPhoto.option(for: model.photo))
            #expect(model.photoResolver.defaultSelection() == oldPhoto.defaultSelection())
            for selection in photoSelections {
                #expect(model.photoResolver.settled(selection) == oldPhoto.settled(selection))
                #expect(model.photoResolver.option(for: selection) == oldPhoto.option(for: selection))
                for row in PhotoRow.allCases {
                    let chips = model.photoResolver.chips(row, for: selection)
                    #expect(chips == oldPhoto.chips(row, for: selection))
                    #expect(model.photoResolver.reasonLine(row, for: selection) == oldPhoto.reasonLine(row, for: selection))
                    for chip in chips {
                        #expect(model.photoResolver.select(row, chipID: chip.id, in: selection) == oldPhoto.select(row, chipID: chip.id, in: selection))
                    }
                }
            }
        }
    }
}
