import Foundation
@testable import OpenCam

/// Stands in for the system's background task: remembers that it began and whether it ended.
@MainActor final class FakeBackgroundWork: BackgroundWork {
    let name: String
    private(set) var endCount = 0
    var isEnded: Bool { endCount > 0 }

    init(name: String) { self.name = name }

    func end() { endCount += 1 }
}
