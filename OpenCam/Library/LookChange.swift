import Foundation

/// What Apply look or Remove look did to the chosen items, and the sentence that says so.
nonisolated struct LookChange: Sendable, Equatable {
    nonisolated enum Action: Sendable { case applied, removed }

    let action: Action
    let photosChanged: Int
    let clipsSkipped: Int
    let newerSkipped: Int
    /// Photos whose edit could not be written or removed.
    var photosFailed = 0

    /// Changed, then each group that is not zero: videos skipped, newer edits skipped, photos that could not be changed.
    var message: String {
        var sentences: [String]
        switch (action, photosChanged) {
        case (_, 0): sentences = ["No photos were changed."]
        case (.applied, 1): sentences = ["Applied to 1 photo."]
        case (.applied, let count): sentences = ["Applied to \(count) photos."]
        case (.removed, 1): sentences = ["Look removed from 1 photo."]
        case (.removed, let count): sentences = ["Look removed from \(count) photos."]
        }
        if clipsSkipped == 1 {
            sentences.append("1 video was skipped.")
        } else if clipsSkipped > 1 {
            sentences.append("\(clipsSkipped) videos were skipped.")
        }
        if newerSkipped == 1 {
            sentences.append("1 photo was edited by a newer version of OpenCam and was skipped.")
        } else if newerSkipped > 1 {
            sentences.append("\(newerSkipped) photos were edited by a newer version of OpenCam and were skipped.")
        }
        if photosFailed == 1 {
            sentences.append("1 photo could not be changed.")
        } else if photosFailed > 1 {
            sentences.append("\(photosFailed) photos could not be changed.")
        }
        return sentences.joined(separator: " ")
    }

    /// The photos Remove look would change, given each item's edit (nil for a clip): those whose edit names a look and is not
    /// from a newer version.
    static func photosToRemove(in edits: [PhotoEdit?]) -> Int {
        edits.count { edit in
            guard let edit, edit.version <= PhotoEdit.currentVersion else { return false }
            return edit.lookName != nil
        }
    }

    /// The photos whose edit Apply look would replace, given each item's edit (nil for a clip): those that have an edit that is
    /// not from a newer version.
    static func editsToReplace(in edits: [PhotoEdit?]) -> Int {
        edits.count { edit in
            guard let edit, edit.version <= PhotoEdit.currentVersion else { return false }
            return !edit.isIdentity
        }
    }
}
