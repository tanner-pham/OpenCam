import Foundation

/// What Apply look or Remove look did to the chosen items, and the sentence that says so.
nonisolated struct LookChange: Sendable, Equatable {
    nonisolated enum Action: Sendable { case applied, removed }

    let action: Action
    let photosChanged: Int
    let clipsSkipped: Int
    let newerSkipped: Int

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
        return sentences.joined(separator: " ")
    }
}
