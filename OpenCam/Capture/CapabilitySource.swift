import Foundation

/// Where the model gets lenses and scanned formats, and where it caches them. `.device` is the real one; tests pass their own.
nonisolated struct CapabilitySource: Sendable {
    let cacheDirectory: URL
    /// A copy of each scan goes here for comparison with the probe report; nil writes no copy.
    let documentsDirectory: URL?
    let discoverLenses: @Sendable () -> [Lens]
    let scan: @Sendable ([Lens]) async throws(CameraSessionError) -> [FormatDescriptor]

    static let device = CapabilitySource(
        cacheDirectory: URL.applicationSupportDirectory.appending(path: "OpenCam"),
        documentsDirectory: URL.documentsDirectory,
        discoverLenses: { LensDiscovery.lenses() },
        scan: { lenses throws(CameraSessionError) in try await CapabilityScanner.scan(lenses: lenses) }
    )
}
