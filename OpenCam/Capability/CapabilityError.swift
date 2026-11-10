import Foundation

nonisolated enum CapabilityError: Error, CustomStringConvertible {
    case fixtureMissing
    case unreadable(path: String, reason: String)
    case unwritable(path: String, reason: String)

    var description: String {
        switch self {
        case .fixtureMissing:
            "[CaptureCapabilities:bundledFixture] Fixture is not in the bundle — {file: CapabilitiesFixture.json}"
        case .unreadable(let path, let reason):
            "[CaptureCapabilities:read] Cannot read capabilities — {path: \(path), reason: \(reason)}"
        case .unwritable(let path, let reason):
            "[CaptureCapabilities:write] Cannot write capabilities — {path: \(path), reason: \(reason)}"
        }
    }
}
