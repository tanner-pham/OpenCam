import Foundation

/// The Library screen's words, kept in one place so tests pin them.
nonisolated enum LibraryCopy {
    static let title = "Library", emptyTitle = "No photos yet", emptyDetail = "Take one or import from Photos."
    static let cannotOpen = "This photo could not be opened.", clipCannotOpen = "This video could not be opened."
    static let deleteFailed = "The items could not be deleted."
    static let saveFailed = "The edit could not be saved."
    static let exportFailed = "The photo could not be exported."
    /// Shown for any save or remove that meets `EditStoreError.newerVersion`.
    static let newerEdit = "This photo was edited by a newer version of OpenCam."
    /// Shown for an edit file that exists but cannot be read; this build never overwrites or removes it.
    static let unreadableEdit = "This photo's edit could not be read."
    static let deleteMessage = "The files and their edits are removed from OpenCam. This cannot be undone."

    /// The sentence after an import; nil when nothing was chosen.
    static func importResult(imported: Int, failed: Int) -> String? {
        let done = imported == 1 ? "Imported 1 photo." : "Imported \(imported) photos."
        switch (imported, failed) {
        case (0, 0): return nil
        case (0, 1): return "The photo could not be imported."
        case (0, _): return "\(failed) photos could not be imported."
        case (_, 0): return done
        default: return done + " \(failed) could not be imported."
        }
    }

    static let removeLookMessage = "Their looks and adjustments are cleared. Masks stay."
    static let replaceEditsMessage = "Their adjustments are replaced by this look. Masks stay."

    static func removeLookTitle(count: Int) -> String {
        count == 1 ? "Remove look from 1 photo?" : "Remove look from \(count) photos?"
    }

    static func replaceEditsTitle(count: Int) -> String {
        count == 1 ? "Replace edits on 1 photo?" : "Replace edits on \(count) photos?"
    }

    static func selectionTitle(count: Int) -> String {
        count == 0 ? "Select items" : "\(count) selected"
    }

    static func deleteTitle(count: Int) -> String {
        count == 1 ? "Delete 1 item?" : "Delete \(count) items?"
    }

    /// Rounded down: 42.5 is "0:42", 62 is "1:02", 3725 is "1:02:05".
    static func duration(seconds: Double) -> String {
        let total = Int(max(0, seconds).rounded(.down))
        let hours = total / 3600, minutes = total % 3600 / 60, secs = total % 60
        let two = { (value: Int) in value < 10 ? "0\(value)" : "\(value)" }
        return hours > 0 ? "\(hours):\(two(minutes)):\(two(secs))" : "\(minutes):\(two(secs))"
    }
}
