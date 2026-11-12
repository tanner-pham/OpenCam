import Foundation

/// A claim on a little time after the app leaves the foreground, so a clip can be finished and saved. Ending it twice is harmless.
@MainActor protocol BackgroundWork: AnyObject {
    func end()
}
