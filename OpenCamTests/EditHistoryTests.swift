import Foundation
import Testing
@testable import OpenCam

@Suite struct EditHistoryTests {
    private func edit(_ exposure: Double) -> PhotoEdit { PhotoEdit(adjustments: Adjustments().setting(.exposure, to: exposure)) }
    private let t0 = Date(timeIntervalSinceReferenceDate: 1000)

    @Test func undoRestoresTheEditBeforeAChange() {
        var history = EditHistory()
        history.record(edit(1), at: t0)
        #expect(history.undo(from: edit(2)) == edit(1))
        #expect(history.redo(from: edit(1)) == edit(2))
    }
    @Test func changesInsideTheWindowAreOneStep() {
        var history = EditHistory()
        history.record(edit(1), at: t0); history.record(edit(2), at: t0 + 0.3); history.record(edit(3), at: t0 + 0.5)
        #expect(history.undo(from: edit(4)) == edit(1))
        #expect(!history.canUndo)
    }
    @Test func changesApartAreTwoSteps() {
        var history = EditHistory()
        history.record(edit(1), at: t0); history.record(edit(2), at: t0 + 1)
        #expect(history.undo(from: edit(3)) == edit(2))
        #expect(history.undo(from: edit(2)) == edit(1))
    }
    @Test func aNewChangeClearsRedo() {
        var history = EditHistory()
        history.record(edit(1), at: t0)
        _ = history.undo(from: edit(2))
        #expect(history.canRedo)
        history.record(edit(1), at: t0 + 5)
        #expect(!history.canRedo)
    }
    @Test func theOldestStepGoesPastTheLimit() {
        var history = EditHistory()
        for step in 0...EditHistory.limit { history.record(edit(Double(step)), at: t0 + Double(step)) }
        var undos = 0
        while history.undo(from: edit(0)) != nil { undos += 1 }
        #expect(undos == 100)
    }
    @Test func undoEndsTheStep() {
        var history = EditHistory()
        history.record(edit(1), at: t0)
        _ = history.undo(from: edit(2))
        history.record(edit(3), at: t0 + 0.1)
        #expect(history.canUndo)
    }
}
