import Testing
import UIKit
@testable import OpenCam

/// How each lens reads in the strip and in its menu: zoom text for the back lenses, a device symbol for the front cameras.
@MainActor @Suite struct LensBadgeTests {
    func lens(_ kind: LensKind, zoom: Double = 1, label: String) -> Lens {
        Lens(id: "\(kind.rawValue)@\(zoom)", kind: kind, deviceUniqueID: "device-\(kind.rawValue)", zoomFactor: zoom, label: label)
    }

    @Test func backLensesKeepTheirZoomText() {
        let ultraWide = LensBadge.make(for: lens(.ultraWide, label: "0.5x"))
        let wide = LensBadge.make(for: lens(.wide, label: "1x"))
        let crop = LensBadge.make(for: lens(.wide, zoom: 2, label: "2x"))
        #expect(ultraWide.shortText == "0.5x"); #expect(wide.shortText == "1x"); #expect(crop.shortText == "2x")
        #expect([ultraWide, wide, crop].allSatisfy { $0.symbol == nil })
        #expect(ultraWide.menuTitle == "Ultra wide"); #expect(wide.menuTitle == "Wide"); #expect(crop.menuTitle == "Wide, 2x crop")
        #expect(ultraWide.rowTitle == "0.5x Ultra wide")
    }

    /// The device names them by their long localized names; the strip shows a symbol of the phone instead.
    @Test func frontCamerasShowASymbolAndNoLongName() throws {
        let outer = LensBadge.make(for: lens(.outerUltraWide, label: "Front Outer Ultra Wide Camera"))
        let inner = LensBadge.make(for: lens(.innerUltraWide, label: "Front Inner Ultra Wide Camera"))
        for badge in [outer, inner] {
            #expect(badge.shortText == nil)
            let symbol = try #require(badge.symbol)
            #expect(UIImage(systemName: symbol) != nil)
        }
        #expect(outer.symbol != inner.symbol)
        #expect(outer.menuTitle == "Front, outer display"); #expect(inner.menuTitle == "Front, inner display")
        #expect(outer.rowTitle == "Front, outer display")
        #expect(UIImage(systemName: LensBadge.backLensSymbol) != nil)
    }

    /// `LensKind` is closed, so the table's unknowns are the kind and zoom pairs it has no row for, such as a 3x wide crop.
    @Test func anUnknownKindFallsBackToItsLabel() {
        let badge = LensBadge.make(for: lens(.wide, zoom: 3, label: "3x"))
        #expect(badge.shortText == "3x"); #expect(badge.symbol == nil); #expect(badge.menuTitle == "3x"); #expect(badge.rowTitle == "3x")
        let ultraWideCrop = LensBadge.make(for: lens(.ultraWide, zoom: 2, label: "Ultra wide 2x"))
        #expect(ultraWideCrop.shortText == "Ultra wide 2x"); #expect(ultraWideCrop.menuTitle == "Ultra wide 2x")
    }

    @Test func menuTitlesAreShortAndDistinct() throws {
        let lenses = try Fixture.load().lenses
        #expect(Set(lenses.map(\.kind)) == [.ultraWide, .wide, .outerUltraWide, .innerUltraWide])
        try #require(lenses.count == 5)
        let titles = lenses.map { LensBadge.make(for: $0).rowTitle }
        #expect(Set(titles).count == 5)
        #expect(titles.allSatisfy { $0.count <= 24 })
    }
}
