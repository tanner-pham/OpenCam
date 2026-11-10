import Foundation
@testable import OpenCam

enum Fixture {
    /// The bundled fixture has no `scanVersion` and decodes as 1; tests use it as a current scan, so the cache reuses it.
    static func load() throws -> CaptureCapabilities {
        var capabilities = try CaptureCapabilities.bundledFixture()
        capabilities.scanVersion = CaptureCapabilities.currentScanVersion
        return capabilities
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
