import Foundation
import Testing
@testable import OpenCam

@Suite struct ErrorJournalTests {
    @Test func linesAreAppendedInOrder() throws {
        let journal = ErrorJournal(fileURL: try TestFiles.directory().appending(path: ErrorJournal.fileName))
        journal.append("first")
        journal.append("second")
        #expect(try String(contentsOf: journal.fileURL, encoding: .utf8) == "first\nsecond\n")
    }

    @Test func anOversizedJournalKeepsItsNewerHalfFromALineStart() throws {
        let journal = ErrorJournal(fileURL: try TestFiles.directory().appending(path: ErrorJournal.fileName))
        let line = String(repeating: "x", count: 999)
        for index in 0..<220 { journal.append("\(index) \(line)") }
        let text = try String(contentsOf: journal.fileURL, encoding: .utf8)
        #expect(text.utf8.count <= ErrorJournal.maxBytes)
        #expect(text.hasSuffix("219 \(line)\n"))
        let first = try #require(text.split(separator: "\n").first)
        #expect(first.hasSuffix(line))                          // the oldest kept line is whole
        #expect(Int(first.prefix { $0 != " " }) != nil)
        #expect(!text.contains("\n0 "))                          // the oldest lines are gone
    }

    @Test func anUnwritablePlaceIsIgnored() throws {
        let missing = try TestFiles.directory().appending(path: "missing", directoryHint: .isDirectory).appending(path: ErrorJournal.fileName)
        ErrorJournal(fileURL: missing).append("lost")
        #expect(!FileManager.default.fileExists(atPath: missing.path(percentEncoded: false)))
    }
}
