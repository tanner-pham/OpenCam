import Foundation
import Testing
@testable import OpenCam

@Suite struct LocalMaskTests {
    private func jsonObject(_ edit: PhotoEdit) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(edit)) as? [String: Any])
    }

    @Test func anEditWithEveryKindOfMaskRoundTrips() throws {
        let strokes = [BrushStroke(dabs: [BrushDab(x: 0.2, y: 0.3, radius: 0.05), BrushDab(x: 0.25, y: 0.35, radius: 0.05)]),
                       BrushStroke(dabs: [BrushDab(x: 0.22, y: 0.31, radius: 0.02)], isErasing: true)]
        var edit = PhotoEdit(adjustments: Adjustments().setting(.exposure, to: 5))
        edit.masks = [
            LocalMask(shape: .linear(start: MaskPoint(x: 0.5, y: 0), end: MaskPoint(x: 0.5, y: 0.5)), adjustments: Adjustments().setting(.shadows, to: 20)),
            LocalMask(shape: .radial(centre: MaskPoint(x: 0.4, y: 0.6), radius: 0.3, feather: 0.5), isInverted: true, adjustments: Adjustments().setting(.saturation, to: -30)),
            LocalMask(shape: .brush(strokes: strokes), adjustments: Adjustments().setting(.tint, to: 10)),
            LocalMask(shape: .subject)]
        let decoded = try JSONDecoder().decode(PhotoEdit.self, from: JSONEncoder().encode(edit))
        #expect(decoded == edit); #expect(decoded.masks.map(\.shape.kind) == [.linear, .radial, .brush, .subject]); #expect(decoded.masks[1].isInverted)
    }

    @Test func aVersionTwoFileOpensWithNoMasks() throws {
        let edit = try JSONDecoder().decode(PhotoEdit.self, from: Data(#"{"adjustments":{"exposure":10},"version":2}"#.utf8))
        #expect(edit.masks == []); #expect(edit.adjustments == Adjustments().setting(.exposure, to: 10)); #expect(edit.version == 2)
    }

    @Test func anEditWithAMaskIsNotIdentity() {
        #expect(PhotoEdit().isIdentity)
        var edit = PhotoEdit(); edit.masks = [LocalMask(shape: .subject)]
        #expect(!edit.isIdentity)
        #expect(!PhotoEdit(masks: [LocalMask(shape: MaskKind.radial.defaultShape)]).isIdentity)
    }

    @Test func anEditWithoutMasksWritesNoMasksKey() throws {
        let plain = try jsonObject(PhotoEdit(adjustments: Adjustments().setting(.exposure, to: 1), lookName: "Warm fade"))
        #expect(plain["masks"] == nil); #expect(plain["lookName"] as? String == "Warm fade"); #expect(plain["version"] as? Int == PhotoEdit.versionWithoutMasks); #expect(plain["adjustments"] != nil)
        #expect(try jsonObject(PhotoEdit(masks: [LocalMask(shape: .subject)]))["masks"] != nil)
    }

    @Test func savedEditIsVersionThree() throws {
        let dir = try TestFiles.directory(), store = EditStore(directory: dir)
        try store.save(PhotoEdit(masks: [LocalMask(shape: .subject)]), stem: "OC_0001")
        #expect(PhotoEdit.currentVersion == 3)
        #expect(try JSONDecoder().decode(EditFileVersion.self, from: Data(contentsOf: store.url(forStem: "OC_0001"))).version == 3)
        #expect(try store.load(stem: "OC_0001").masks.count == 1)
    }

    @Test func anEditWithoutMasksSavesAsVersionTwo() throws {
        let dir = try TestFiles.directory(), store = EditStore(directory: dir), url = store.url(forStem: "OC_0001")
        func stored() throws -> Int? { try JSONDecoder().decode(EditFileVersion.self, from: Data(contentsOf: url)).version }
        var edit = PhotoEdit(adjustments: Adjustments().setting(.exposure, to: 1), lookName: "Warm fade", masks: [LocalMask(shape: .subject)])
        try store.save(edit, stem: "OC_0001"); #expect(try stored() == 3)
        edit.masks = []; try store.save(edit, stem: "OC_0001"); #expect(try stored() == 2)
        let reloaded = try store.load(stem: "OC_0001")
        #expect(reloaded.adjustments == edit.adjustments); #expect(reloaded.lookName == "Warm fade"); #expect(reloaded.masks == [])
    }

    @Test func maskKindTitlesAndDefaults() {
        #expect(MaskKind.allCases.map(\.title) == ["Linear", "Radial", "Brush", "Subject"])
        #expect(MaskKind.linear.defaultShape == .linear(start: MaskPoint(x: 0.5, y: 0), end: MaskPoint(x: 0.5, y: 0.5)))
        #expect(MaskKind.radial.defaultShape == .radial(centre: MaskPoint(x: 0.5, y: 0.5), radius: 0.3, feather: 0.5))
        #expect(MaskKind.brush.defaultShape == .brush(strokes: [])); #expect(MaskKind.subject.defaultShape == .subject)
        for kind in MaskKind.allCases { #expect(kind.defaultShape.kind == kind) }
        #expect(LocalMask.keys == [.exposure, .contrast, .highlights, .shadows, .temperature, .tint, .saturation])
    }
}
