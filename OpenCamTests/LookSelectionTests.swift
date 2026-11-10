import Foundation
import Testing
@testable import OpenCam

/// Which tile in the Looks group shows as selected: decided by the edit's values; the look name the edit copied only picks
/// one when several looks have those values, so exactly one tile is ever marked.
@Suite struct LookSelectionTests {
    static func look(_ name: String, _ adjustments: Adjustments) -> Look {
        Look(id: UUID(), name: name, adjustments: adjustments, createdAt: .now)
    }

    /// The tiles marked for an edit, "None" as nil.
    static func marked(_ looks: [Look], for adjustments: Adjustments, lookName: String?) -> [String] {
        let tiles: [Look?] = [nil] + looks.map { $0 }
        return tiles.filter { LookSelection.isSelected($0, among: looks, for: adjustments, lookName: lookName) }
            .map { $0?.name ?? "None" }
    }

    @Test func aLookIsSelectedWhenTheEditHasItsValues() {
        let warm = Self.look("Warm fade", LookSeeder.warmFade)
        #expect(LookSelection.isSelected(warm, among: [warm], for: LookSeeder.warmFade, lookName: "Warm fade"))
        #expect(!LookSelection.isSelected(nil, among: [warm], for: LookSeeder.warmFade, lookName: "Warm fade"))
        // The values decide, even when the edit recorded no name or another one.
        #expect(LookSelection.isSelected(warm, among: [warm], for: LookSeeder.warmFade, lookName: nil))
        #expect(LookSelection.isSelected(warm, among: [warm], for: LookSeeder.warmFade, lookName: "Old name"))
    }

    @Test func twoLooksWithOneNameAreToldApartByTheirValues() {
        let first = Self.look("Golden", Adjustments().setting(.temperature, to: 30))
        let second = Self.look("Golden", Adjustments().setting(.temperature, to: 60))
        let edit = Adjustments().setting(.temperature, to: 60)
        #expect(Self.marked([first, second], for: edit, lookName: "Golden") == ["Golden"])
        #expect(LookSelection.isSelected(second, among: [first, second], for: edit, lookName: "Golden"))
    }

    @Test func aHandMadeEditSelectsNothing() {
        let warm = Self.look("Warm fade", LookSeeder.warmFade)
        let edit = LookSeeder.warmFade.setting(.exposure, to: 1.5)
        #expect(Self.marked([warm], for: edit, lookName: "Warm fade").isEmpty)
    }

    @Test func noneIsSelectedOnlyWithNoAdjustments() {
        let warm = Self.look("Warm fade", LookSeeder.warmFade)
        #expect(Self.marked([warm], for: Adjustments(), lookName: nil) == ["None"])
        #expect(Self.marked([warm], for: Adjustments().setting(.grain, to: 1), lookName: nil).isEmpty)
    }

    /// A duplicated look has the original's values: only the one the edit was applied from is marked.
    @Test func looksWithTheSameValuesMarkTheOneTheEditNamed() {
        let original = Self.look("QA look", LookSeeder.warmFade), copy = Self.look("QA look copy", LookSeeder.warmFade)
        #expect(Self.marked([original, copy], for: LookSeeder.warmFade, lookName: "QA look") == ["QA look"])
        #expect(Self.marked([original, copy], for: LookSeeder.warmFade, lookName: "QA look copy") == ["QA look copy"])
    }

    /// When no matching look has the recorded name (renamed, or none recorded), the first matching look in the list is marked.
    @Test func looksWithTheSameValuesAndNoNamedOneMarkTheFirst() {
        let first = Self.look("A", LookSeeder.warmFade), second = Self.look("B", LookSeeder.warmFade)
        #expect(Self.marked([first, second], for: LookSeeder.warmFade, lookName: "Renamed since") == ["A"])
        #expect(Self.marked([first, second], for: LookSeeder.warmFade, lookName: nil) == ["A"])
        #expect(Self.marked([second, first], for: LookSeeder.warmFade, lookName: nil) == ["B"])
    }

    /// The recorded name only chooses among looks with the edit's values: a look of that name with other values is not marked.
    @Test func theRecordedNameNeverSelectsALookWithOtherValues() {
        let named = Self.look("Golden", Adjustments().setting(.temperature, to: 30))
        let matching = Self.look("Other", Adjustments().setting(.temperature, to: 60))
        #expect(Self.marked([named, matching], for: Adjustments().setting(.temperature, to: 60), lookName: "Golden") == ["Other"])
    }

    /// Values that read the same compare the same: 0.1 + 0.2 is on the exposure step 0.3.
    @Test func valuesAreComparedOnTheirSteps() {
        let look = Self.look("Bright", Adjustments().setting(.exposure, to: 0.3))
        #expect(LookSelection.isSelected(look, among: [look], for: Adjustments().setting(.exposure, to: 0.1 + 0.2), lookName: "Bright"))
    }
}
