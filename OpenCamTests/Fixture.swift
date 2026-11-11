import Foundation
@testable import OpenCam

enum Fixture {
    /// The bundled fixture has no `scanVersion` and decodes as 1; tests use it as a current scan, so the cache reuses it.
    static func load() throws -> CaptureCapabilities {
        var capabilities = try CaptureCapabilities.bundledFixture()
        capabilities.scanVersion = CaptureCapabilities.currentScanVersion
        return capabilities
    }

    /// The phone's own scan (6,192 video and 25 photo options across 5 lenses), copied as a resource of this test bundle.
    static func loadDuo() throws -> CaptureCapabilities {
        guard let url = Bundle.allBundles.lazy.compactMap({ $0.url(forResource: "DuoCapabilities", withExtension: "json") }).first else {
            throw FixtureError.duoMissing
        }
        return try CaptureCapabilities.decode(try Data(contentsOf: url))
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
    case duoMissing

    var description: String {
        switch self {
        case .defaultsUnavailable: "[Fixture:freshDefaults] Cannot create UserDefaults suite — {}"
        case .duoMissing: "[Fixture:loadDuo] DuoCapabilities.json is not in the test bundle — {}"
        }
    }
}
