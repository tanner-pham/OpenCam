import Foundation
@testable import OpenCam

enum Fixture {
    static func load() throws -> CaptureCapabilities {
        try CaptureCapabilities.bundledFixture()
    }

    static func freshDefaults() throws -> UserDefaults {
        guard let defaults = UserDefaults(suiteName: UUID().uuidString) else {
            throw FixtureError.defaultsUnavailable
        }
        return defaults
    }
}

enum FixtureError: Error, CustomStringConvertible {
    case defaultsUnavailable

    var description: String { "[Fixture:freshDefaults] Cannot create UserDefaults suite — {}" }
}
