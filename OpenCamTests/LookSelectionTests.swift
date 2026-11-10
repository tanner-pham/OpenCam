import Foundation
import Testing
@testable import OpenCam

/// Which tile in the Looks group shows as selected: decided by the edit's values, never by the look name the edit copied.
@Suite struct LookSelectionTests {
    static func look(_ name: String, _ adjustments: Adjustments) -> Look {
        Look(id: UUID(), name: name, adjustments: adjustments, createdAt: .now)
    }

    @Test func aLookIsSelectedWhenTheEditHasItsValues() {
        let warm = Self.look("Warm fade", LookSeeder.warmFade)
        #expect(LookSelection.isSelected(warm, for: LookSeeder.warmFade))
        #expect(!LookSelection.isSelected(nil, for: LookSeeder.warmFade))
    }

    @Test func twoLooksWithOneNameAreToldApartByTheirValues() {
        let first = Self.look("Golden", Adjustments().setting(.temperature, to: 30))
        let second = Self.look("Golden", Adjustments().setting(.temperature, to: 60))
        let edit = Adjustments().setting(.temperature, to: 60)
        #expect(!LookSelection.isSelected(first, for: edit)); #expect(LookSelection.isSelected(second, for: edit))
    }

    @Test func aHandMadeEditSelectsNothing() {
        let warm = Self.look("Warm fade", LookSeeder.warmFade)
        let edit = LookSeeder.warmFade.setting(.exposure, to: 1.5)
        #expect(!LookSelection.isSelected(nil, for: edit)); #expect(!LookSelection.isSelected(warm, for: edit))
    }

    @Test func noneIsSelectedOnlyWithNoAdjustments() {
        #expect(LookSelection.isSelected(nil, for: Adjustments()))
        #expect(!LookSelection.isSelected(nil, for: Adjustments().setting(.grain, to: 1)))
        #expect(!LookSelection.isSelected(Self.look("Warm fade", LookSeeder.warmFade), for: Adjustments()))
    }

    @Test func looksWithTheSameValuesAreBothSelected() {
        let first = Self.look("A", LookSeeder.warmFade), second = Self.look("B", LookSeeder.warmFade)
        #expect(LookSelection.isSelected(first, for: LookSeeder.warmFade)); #expect(LookSelection.isSelected(second, for: LookSeeder.warmFade))
    }

    /// Values that read the same compare the same: 0.1 + 0.2 is on the exposure step 0.3.
    @Test func valuesAreComparedOnTheirSteps() {
        let look = Self.look("Bright", Adjustments().setting(.exposure, to: 0.3))
        #expect(LookSelection.isSelected(look, for: Adjustments().setting(.exposure, to: 0.1 + 0.2)))
    }
}
