import CoreImage
import CoreGraphics
import Foundation
import Testing
@testable import OpenCam

@MainActor @Suite struct EditorModelTests {
    @Test func fortyEightMegapixelOriginalRendersOnlyTheProxy() async throws {   // Review Focus 2
        let (model, _, _) = try await EditorFixture.make(width: 8064, height: 6048)
        #expect(model.phase == .ready); #expect(model.proxySize == CGSize(width: 2048, height: 1536))
        let rendersBefore = model.previewRenderCount
        for step in 1...30 { model.adjustments.exposure = Double(step) / 10 }
        await model.waitForPreview()
        #expect(model.previewRenderCount > rendersBefore)   // the slider change really rendered
        let size = try #require(model.lastRenderPixelSize)   // measured on the CGImage the renderer returned
        #expect(max(size.width, size.height) <= 2048); #expect(size == CGSize(width: 2048, height: 1536))
        #expect(model.renderedAdjustments == model.adjustments); #expect(model.previewRenderCount <= 3)
    }
    @Test func opensWithItsSavedEdit() async throws {
        let dir = try TestFiles.directory()
        _ = try TestFiles.writeJPEG(width: 400, height: 300, rgb: SIMD3(0.5, 0.5, 0.5), to: dir.appending(path: "OC_0001.JPG"))
        try EditStore(directory: dir).save(PhotoEdit(adjustments: Adjustments().setting(.contrast, to: 25), lookName: "Warm fade"), stem: "OC_0001")
        let item = try #require(LibraryScanner.items(in: dir).first)
        let model = EditorModel(item: item, edits: EditStore(directory: dir), looks: try LookStore(directory: TestFiles.directory()))
        await model.load()
        #expect(model.adjustments.contrast == 25); #expect(model.lookName == "Warm fade"); #expect(!model.hasChanges); #expect(model.preview != nil)
    }
    @Test func theOverlayDrawsWhenMasksLoadBeforeThePicture() async throws {
        let dir = try TestFiles.directory()
        _ = try TestFiles.writeJPEG(width: 400, height: 300, rgb: SIMD3(0.5, 0.5, 0.5), to: dir.appending(path: "OC_0001.JPG"))
        let mask = LocalMask(shape: MaskKind.radial.defaultShape)
        try EditStore(directory: dir).save(PhotoEdit(masks: [mask]), stem: "OC_0001")
        let item = try #require(LibraryScanner.items(in: dir).first)
        let model = EditorModel(item: item, edits: EditStore(directory: dir), looks: try LookStore(directory: TestFiles.directory()), group: .masks)
        await model.load()
        await model.waitForMaskOverlay()
        #expect(model.maskOverlay != nil)
    }
    @Test func resetsAndSave() async throws {
        let (model, dir, _) = try await EditorFixture.make(width: 400, height: 300)
        model.adjustments.shadows = 40; model.adjustments.tint = -10; #expect(model.hasChanges)
        model.reset(.shadows); #expect(model.adjustments.shadows == 0); #expect(model.adjustments.tint == -10)
        #expect(model.save()); #expect(try EditStore(directory: dir).load(stem: "OC_0001").adjustments.tint == -10)
        model.resetAll(); #expect(model.adjustments.isIdentity); #expect(model.save())
        #expect(!FileManager.default.fileExists(atPath: dir.appending(path: "OC_0001.edit.json").path(percentEncoded: false)))
    }
    @Test func originalRemovedWhileOpenSaysCannotOpen() async throws {   // Review Focus 5
        let (model, dir, _) = try await EditorFixture.make(width: 400, height: 300)
        try FileManager.default.removeItem(at: dir.appending(path: "OC_0001.JPG"))
        model.adjustments.exposure = 1
        await model.waitForPreview()
        #expect(!model.save()); #expect(model.phase == .failed("This photo could not be opened."))
        #expect(!FileManager.default.fileExists(atPath: dir.appending(path: "OC_0001.edit.json").path(percentEncoded: false)))
    }
    @Test func undecodableOriginalSaysCannotOpen() async throws {
        let dir = try TestFiles.directory()
        try Data("nope".utf8).write(to: dir.appending(path: "OC_0001.JPG"))
        let model = EditorModel(item: try #require(LibraryScanner.items(in: dir).first), edits: EditStore(directory: dir), looks: try LookStore(directory: TestFiles.directory()))
        await model.load()
        #expect(model.phase == .failed("This photo could not be opened.")); #expect(model.preview == nil)
    }
    @Test func editFromANewerVersionOpensReadOnly() async throws {
        let dir = try TestFiles.directory()
        _ = try TestFiles.writeJPEG(width: 400, height: 300, rgb: SIMD3(0.5, 0.5, 0.5), to: dir.appending(path: "OC_0001.JPG"))
        let newer = Data(#"{"version": 99, "adjustments": {"exposure": 1}, "masks": []}"#.utf8), editURL = dir.appending(path: "OC_0001.edit.json")
        try newer.write(to: editURL)
        let model = EditorModel(item: try #require(LibraryScanner.items(in: dir).first), edits: EditStore(directory: dir), looks: try LookStore(directory: TestFiles.directory()))
        await model.load()
        #expect(model.phase == .failed("This photo was edited by a newer version of OpenCam."))
        #expect(!model.save()); #expect(try Data(contentsOf: editURL) == newer)
    }
    @Test func firstRenderThatFailsSaysCannotOpen() async throws {
        let dir = try TestFiles.directory()
        _ = try TestFiles.writeJPEG(width: 400, height: 300, rgb: SIMD3(0.5, 0.5, 0.5), to: dir.appending(path: "OC_0001.JPG"))
        let model = EditorModel(item: try #require(LibraryScanner.items(in: dir).first), edits: EditStore(directory: dir),
                                looks: try LookStore(directory: TestFiles.directory()), renderPreview: { _, _, _ in nil })
        await model.load()
        #expect(model.phase == .failed("This photo could not be opened.")); #expect(model.preview == nil)
    }
    @Test func unsavedChangesFollowTheOpeningValues() async throws {
        let dir = try TestFiles.directory()
        _ = try TestFiles.writeJPEG(width: 400, height: 300, rgb: SIMD3(0.5, 0.5, 0.5), to: dir.appending(path: "OC_0001.JPG"))
        try EditStore(directory: dir).save(PhotoEdit(adjustments: Adjustments().setting(.contrast, to: 25)), stem: "OC_0001")
        let model = EditorModel(item: try #require(LibraryScanner.items(in: dir).first), edits: EditStore(directory: dir), looks: try LookStore(directory: TestFiles.directory()))
        await model.load()
        #expect(!model.hasUnsavedChanges)                                   // unchanged
        model.adjustments.contrast = 40; #expect(model.hasUnsavedChanges)   // changed
        model.adjustments.contrast = 25; #expect(!model.hasUnsavedChanges)  // back to the opening value
        model.resetAll(); #expect(model.hasUnsavedChanges)                  // the opening edit was not empty
    }
    @Test func exposureBackOnASavedValueIsNotAChange() async throws {
        let dir = try TestFiles.directory()
        _ = try TestFiles.writeJPEG(width: 400, height: 300, rgb: SIMD3(0.5, 0.5, 0.5), to: dir.appending(path: "OC_0001.JPG"))
        try EditStore(directory: dir).save(PhotoEdit(adjustments: Adjustments().setting(.exposure, to: 0.3)), stem: "OC_0001")
        let model = EditorModel(item: try #require(LibraryScanner.items(in: dir).first), edits: EditStore(directory: dir), looks: try LookStore(directory: TestFiles.directory()))
        await model.load()
        #expect(AdjustmentKey.exposure.snapped(0.1 + 0.2) == 0.3); #expect(AdjustmentKey.exposure.snapped(3 * 0.1) == 0.3)
        model.adjustments.exposure = 0.7; model.adjustments.exposure = 0.1 + 0.2   // 0.30000000000000004, raw
        #expect(!model.hasUnsavedChanges)
        model.adjustments.exposure = AdjustmentKey.exposure.snapped(0.3 + 0.1)     // one step
        #expect(model.hasUnsavedChanges)
    }
    @Test func newerVersionEditHasNoUnsavedChanges() async throws {
        let dir = try TestFiles.directory()
        _ = try TestFiles.writeJPEG(width: 400, height: 300, rgb: SIMD3(0.5, 0.5, 0.5), to: dir.appending(path: "OC_0001.JPG"))
        try Data(#"{"version": 99, "adjustments": {"exposure": 1}}"#.utf8).write(to: dir.appending(path: "OC_0001.edit.json"))
        let model = EditorModel(item: try #require(LibraryScanner.items(in: dir).first), edits: EditStore(directory: dir), looks: try LookStore(directory: TestFiles.directory()))
        await model.load()
        #expect(!model.hasUnsavedChanges)
        model.adjustments.exposure = 2; #expect(!model.hasUnsavedChanges)   // read-only: nothing can be saved, so nothing is lost
    }

    @Test func undoTakesASliderDragBackInOneStep() async throws {
        let clock = TestClock()
        let (model, _, _) = try await EditorFixture.make(width: 400, height: 300, now: { clock.date })
        for value in [10.0, 20, 30] { model.adjustments.exposure = value; clock.advance(0.2) }
        model.undo(); #expect(model.adjustments.exposure == 0)
        model.redo(); #expect(model.adjustments.exposure == 30)
    }
    @Test func applyingALookIsOneUndoStep() async throws {
        let clock = TestClock()
        let (model, _, _) = try await EditorFixture.make(width: 400, height: 300, now: { clock.date })
        #expect(!model.canUndo)   // loading is not a step
        model.applyLook(Look(id: UUID(), name: "Warm", adjustments: Adjustments().setting(.contrast, to: 20), createdAt: Date()))
        #expect(model.lookName == "Warm")
        model.undo(); #expect(model.adjustments.isIdentity); #expect(model.lookName == nil); #expect(!model.canUndo)
    }
    @Test func resetAllIsOneUndoStep() async throws {
        let clock = TestClock()
        let (model, _, _) = try await EditorFixture.make(width: 400, height: 300, now: { clock.date })
        model.adjustments.exposure = 10; clock.advance(0.1)
        model.resetAll(); clock.advance(0.1)
        #expect(model.adjustments.isIdentity)
        model.undo(); #expect(model.adjustments.exposure == 10)
        model.undo(); #expect(model.adjustments.exposure == 0); #expect(!model.canUndo)
    }
    @Test func aLookTappedRightAfterADragIsItsOwnStep() async throws {
        let clock = TestClock()
        let (model, _, _) = try await EditorFixture.make(width: 400, height: 300, now: { clock.date })
        model.adjustments.exposure = 10; clock.advance(0.1); model.adjustments.exposure = 20; clock.advance(0.2)
        model.applyLook(Look(id: UUID(), name: "Warm", adjustments: Adjustments().setting(.contrast, to: 20), createdAt: Date()))
        model.undo(); #expect(model.adjustments.exposure == 20); #expect(model.adjustments.contrast == 0); #expect(model.lookName == nil)
        model.undo(); #expect(model.adjustments.exposure == 0); #expect(!model.canUndo)
    }
    @Test func savingALookIsNotAnUndoStep() async throws {
        let clock = TestClock()
        let (model, _, _) = try await EditorFixture.make(width: 400, height: 300, now: { clock.date })
        model.adjustments.exposure = 10; clock.advance(2)
        _ = try model.saveAsLook(named: "Mine")
        #expect(model.lookName == "Mine")
        model.undo(); #expect(model.adjustments.exposure == 0); #expect(!model.canUndo)
    }
    @Test func addingAMaskSelectsIt() async throws {
        let (model, _, _) = try await EditorFixture.make(width: 400, height: 300)
        #expect(model.masks.isEmpty); #expect(model.selectedMask == nil)
        model.addMask(.linear); model.addMask(.radial)
        #expect(model.masks.map(\.shape) == [MaskKind.linear.defaultShape, MaskKind.radial.defaultShape])
        #expect(model.selectedMaskID == model.masks[1].id); #expect(model.selectedMask == model.masks[1])
    }
    @Test func deletingAMaskSelectsTheOneBefore() async throws {
        let (model, _, _) = try await EditorFixture.make(width: 400, height: 300)
        model.addMask(.linear); model.addMask(.radial); model.addMask(.brush)
        let ids = model.masks.map(\.id)
        model.deleteSelectedMask(); #expect(model.masks.map(\.id) == [ids[0], ids[1]]); #expect(model.selectedMaskID == ids[1])
        model.selectedMaskID = ids[0]; model.deleteSelectedMask()
        #expect(model.masks.map(\.id) == [ids[1]]); #expect(model.selectedMaskID == ids[1])
        model.deleteSelectedMask(); #expect(model.masks.isEmpty); #expect(model.selectedMaskID == nil)
        model.deleteSelectedMask(); #expect(model.masks.isEmpty)
    }
    @Test func aMaskSliderChangesOnlyTheSelectedMask() async throws {
        let (model, _, _) = try await EditorFixture.make(width: 400, height: 300)
        model.addMask(.linear); model.addMask(.radial)
        let first = model.masks[0]
        model.updateSelectedMask { $0.adjustments[.exposure] = 1.5 }
        #expect(model.masks[0] == first); #expect(model.masks[1].adjustments[.exposure] == 1.5); #expect(model.adjustments.isIdentity)
        model.updateSelectedMask { $0.isInverted = true }
        #expect(model.masks[1].isInverted); #expect(!model.masks[0].isInverted)
    }
    @Test func masksAreSavedAndReadBack() async throws {
        let (model, dir, _) = try await EditorFixture.make(width: 400, height: 300)
        model.addMask(.radial); model.updateSelectedMask { $0.adjustments[.saturation] = -30; $0.isInverted = true }
        #expect(model.hasChanges); #expect(model.save()); #expect(!model.hasChanges)
        let item = try #require(LibraryScanner.items(in: dir).first)
        let reopened = EditorModel(item: item, edits: EditStore(directory: dir), looks: try LookStore(directory: TestFiles.directory()))
        await reopened.load()
        #expect(reopened.masks == model.masks); #expect(!reopened.hasChanges)
    }
    @Test func resetAllClearsMasks() async throws {
        let (model, _, _) = try await EditorFixture.make(width: 400, height: 300)
        model.addMask(.linear); model.resetAll()
        #expect(model.masks.isEmpty); #expect(model.selectedMaskID == nil); #expect(model.currentEdit.isIdentity)
    }
    @Test func applyingALookKeepsMasks() async throws {
        let (model, _, _) = try await EditorFixture.make(width: 400, height: 300)
        model.addMask(.linear)
        model.applyLook(Look(id: UUID(), name: "Warm", adjustments: Adjustments().setting(.contrast, to: 20), createdAt: Date()))
        #expect(model.masks.count == 1); #expect(model.adjustments.contrast == 20)
        model.applyLook(nil); #expect(model.masks.count == 1)
    }
    @Test func savingALookLeavesMasksOut() async throws {
        let (model, _, _) = try await EditorFixture.make(width: 400, height: 300)
        model.adjustments.exposure = 1; model.addMask(.linear); model.updateSelectedMask { $0.adjustments[.exposure] = 2 }
        let look = try model.saveAsLook(named: "Mine")
        #expect(look.adjustments == model.adjustments); #expect(look.adjustments.exposure == 1); #expect(model.masks.count == 1)
    }
    @Test func invertRightAfterASliderMoveIsItsOwnStep() async throws {
        let clock = TestClock()
        let (model, _, _) = try await EditorFixture.make(width: 400, height: 300, now: { clock.date })
        model.addMask(.linear); clock.advance(0.1)
        model.updateSelectedMask { $0.adjustments[.exposure] = 1 }; clock.advance(0.1)
        model.toggleSelectedMaskInverted()
        #expect(model.selectedMask?.isInverted == true)
        model.undo()
        #expect(model.selectedMask?.isInverted == false); #expect(model.selectedMask?.adjustments[.exposure] == 1)
        model.undo(); #expect(model.selectedMask?.adjustments[.exposure] == 0)
    }
    @Test func savingALookClearsRedo() async throws {
        let clock = TestClock()
        let (model, _, _) = try await EditorFixture.make(width: 400, height: 300, now: { clock.date })
        model.adjustments.exposure = 1; clock.advance(1)
        model.undo(); #expect(model.canRedo)
        _ = try model.saveAsLook(named: "Mine")
        #expect(!model.canRedo); #expect(model.canUndo == false)
    }
    @Test func deletingAMaskIsOneUndoStep() async throws {
        let clock = TestClock()
        let (model, _, _) = try await EditorFixture.make(width: 400, height: 300, now: { clock.date })
        model.addMask(.linear); clock.advance(0.1)
        model.deleteSelectedMask(); clock.advance(0.1)
        #expect(model.masks.isEmpty)
        model.undo(); #expect(model.masks.count == 1); #expect(model.selectedMask != nil)
        model.undo(); #expect(model.masks.isEmpty); #expect(model.selectedMaskID == nil); #expect(!model.canUndo)
        model.redo(); #expect(model.masks.count == 1)
    }
    @Test func aStrokeIsOneUndoStep() async throws {
        let clock = TestClock()
        let (model, _, _) = try await EditorFixture.make(width: 400, height: 300, now: { clock.date })
        model.addMask(.brush); clock.advance(0.1)
        model.beginStroke(at: MaskPoint(x: 0.1, y: 0.5), pressure: nil)
        for index in 1...5 {
            clock.advance(1)   // slower than the coalescing window
            model.continueStroke(at: MaskPoint(x: 0.1 + 0.15 * Double(index), y: 0.5), pressure: nil)
        }
        model.endStroke()
        guard case let .brush(strokes)? = model.selectedMask?.shape else { Issue.record("not a brush"); return }
        #expect(strokes.count == 1); #expect(strokes[0].dabs.count == 6)
        model.undo()
        guard case let .brush(after)? = model.selectedMask?.shape else { Issue.record("not a brush"); return }
        #expect(after.isEmpty); #expect(model.masks.count == 1)
        model.undo(); #expect(model.masks.isEmpty)
        model.redo(); model.redo()
        guard case let .brush(again)? = model.selectedMask?.shape else { Issue.record("not a brush"); return }
        #expect(again.count == 1)
    }
    @Test func twoStrokesAreTwoUndoSteps() async throws {
        let clock = TestClock()
        let (model, _, _) = try await EditorFixture.make(width: 400, height: 300, now: { clock.date })
        model.addMask(.brush); clock.advance(0.1)
        model.beginStroke(at: MaskPoint(x: 0.2, y: 0.2), pressure: nil); model.endStroke(); clock.advance(0.1)
        model.isErasing = true
        model.beginStroke(at: MaskPoint(x: 0.2, y: 0.2), pressure: nil); model.endStroke()
        model.undo()
        guard case let .brush(strokes)? = model.selectedMask?.shape else { Issue.record("not a brush"); return }
        #expect(strokes.count == 1); #expect(!strokes[0].isErasing)
    }
    @Test func undoDuringAStrokeEndsItAndKeepsEarlierStrokes() async throws {
        let clock = TestClock()
        let (model, _, _) = try await EditorFixture.make(width: 400, height: 300, now: { clock.date })
        model.addMask(.brush); clock.advance(0.1)
        model.beginStroke(at: MaskPoint(x: 0.2, y: 0.2), pressure: nil)
        model.continueStroke(at: MaskPoint(x: 0.4, y: 0.2), pressure: nil); model.endStroke(); clock.advance(0.1)
        guard case let .brush(strokeA)? = model.selectedMask?.shape else { Issue.record("not a brush"); return }
        model.beginStroke(at: MaskPoint(x: 0.2, y: 0.8), pressure: nil)
        model.continueStroke(at: MaskPoint(x: 0.4, y: 0.8), pressure: nil)
        model.undo()
        model.continueStroke(at: MaskPoint(x: 0.9, y: 0.8), pressure: nil)
        guard case let .brush(strokes)? = model.selectedMask?.shape else { Issue.record("not a brush"); return }
        #expect(strokes == strokeA); #expect(strokes.count == 1)
    }
    @Test func deletingTheMaskDuringAStrokeEndsIt() async throws {
        let (model, _, _) = try await EditorFixture.make(width: 400, height: 300)
        model.addMask(.brush)
        model.beginStroke(at: MaskPoint(x: 0.2, y: 0.2), pressure: nil)
        model.deleteSelectedMask()
        model.addMask(.brush)
        model.beginStroke(at: MaskPoint(x: 0.5, y: 0.5), pressure: nil)   // ignored while a stroke is open
        guard case let .brush(strokes)? = model.selectedMask?.shape else { Issue.record("not a brush"); return }
        #expect(strokes.count == 1)
    }
    @Test func paintingNeedsABrushMaskSelected() async throws {
        let (model, _, _) = try await EditorFixture.make(width: 400, height: 300)
        model.addMask(.linear)
        let before = model.masks
        model.beginStroke(at: MaskPoint(x: 0.5, y: 0.5), pressure: nil)
        model.continueStroke(at: MaskPoint(x: 0.9, y: 0.9), pressure: nil)
        model.endStroke()
        #expect(model.masks == before)
    }
    @Test func brushSizeMapsToARadius() async throws {
        let (model, _, _) = try await EditorFixture.make(width: 400, height: 300)
        #expect(model.brushSize == 30)
        model.brushSize = 1; #expect(abs(model.brushRadius - 0.01) < 1e-9)
        model.brushSize = 100; #expect(abs(model.brushRadius - 0.15) < 1e-9)
    }

    // MARK: Subject masks

    private func pixel(_ image: CGImage, x: Int, y: Int) throws -> Float { try PixelReader.rgb(CIImage(cgImage: image), x: x, y: y).x }
    private func subjectModel(find: @escaping @Sendable (CIImage) async -> SubjectSearch) async throws -> EditorModel {
        let captures = try TestFiles.directory()
        _ = try TestFiles.writeJPEG(width: 400, height: 300, rgb: SIMD3(0.5, 0.5, 0.5), to: captures.appending(path: "OC_0001.JPG"))
        let item = try #require(LibraryScanner.items(in: captures).first)
        let model = EditorModel(item: item, edits: EditStore(directory: captures), looks: try LookStore(directory: TestFiles.directory()), findSubject: find)
        await model.load()
        return model
    }

    @Test func aSubjectMaskRendersWithTheFoundSubject() async throws {
        let model = try await subjectModel { image in
            let half = CGRect(x: image.extent.minX, y: image.extent.minY, width: image.extent.width / 2, height: image.extent.height)
            return .found(CIImage(color: .white).cropped(to: half).composited(over: CIImage(color: .black).cropped(to: image.extent)))
        }
        model.addMask(.subject); model.updateSelectedMask { $0.adjustments[.exposure] = 1.5 }
        await model.waitForSubject()
        let preview = try #require(model.preview)
        #expect(model.subjectState == .found)
        #expect(try pixel(preview, x: 50, y: 150) - pixel(preview, x: 350, y: 150) > 0.1)
    }

    @Test func noSubjectFoundLeavesThePhotoUnchanged() async throws {
        let model = try await subjectModel { _ in .notFound }
        let before = try pixel(try #require(model.preview), x: 50, y: 150)
        model.addMask(.subject); model.updateSelectedMask { $0.adjustments[.exposure] = 1.5 }
        await model.waitForSubject()
        let preview = try #require(model.preview)
        #expect(model.subjectState == .notFound)
        #expect(abs(try pixel(preview, x: 50, y: 150) - before) < 0.01); #expect(abs(try pixel(preview, x: 350, y: 150) - before) < 0.01)
    }

    @Test func aFailedSubjectSearchSaysSo() async throws {
        let model = try await subjectModel { _ in .failed }
        let before = try pixel(try #require(model.preview), x: 50, y: 150)
        model.addMask(.subject); model.updateSelectedMask { $0.adjustments[.exposure] = 1.5 }
        await model.waitForSubject()
        #expect(model.subjectState == .failed)
        #expect(try pixel(try #require(model.preview), x: 50, y: 150) == before)
    }

    @Test func closingTheEditorCancelsTheSubjectSearch() async throws {
        let model = try await subjectModel { image in
            try? await Task.sleep(for: .milliseconds(200))
            return .found(CIImage(color: .white).cropped(to: image.extent))
        }
        model.addMask(.subject)
        model.cancelSubjectSearch()
        await model.waitForSubject()
        #expect(model.subjectState == .finding)   // the late result was dropped
    }

    @Test func theSubjectIsFoundOncePerOpen() async throws {
        let calls = Counter()
        let model = try await subjectModel { _ in calls.increment(); return .notFound }
        #expect(model.subjectState == .notNeeded); #expect(calls.value == 0)
        model.addMask(.subject); model.addMask(.subject)
        await model.waitForSubject()
        model.deleteSelectedMask(); model.deleteSelectedMask(); model.addMask(.subject)
        await model.waitForSubject()
        #expect(calls.value == 1); #expect(model.subjectState == .notFound)
    }

    @Test func aSavedSubjectMaskLooksForTheSubjectOnOpen() async throws {
        let captures = try TestFiles.directory()
        _ = try TestFiles.writeJPEG(width: 400, height: 300, rgb: SIMD3(0.5, 0.5, 0.5), to: captures.appending(path: "OC_0001.JPG"))
        try EditStore(directory: captures).save(PhotoEdit(masks: [LocalMask(shape: .subject)]), stem: "OC_0001")
        let calls = Counter()
        let item = try #require(LibraryScanner.items(in: captures).first)
        let model = EditorModel(item: item, edits: EditStore(directory: captures), looks: try LookStore(directory: TestFiles.directory()),
                                findSubject: { _ in calls.increment(); return .notFound })
        await model.load(); await model.waitForSubject()
        #expect(calls.value == 1); #expect(model.subjectState == .notFound)
    }
}

nonisolated final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}

nonisolated final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSinceReferenceDate: 1000)
    var date: Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current += seconds } }
}
