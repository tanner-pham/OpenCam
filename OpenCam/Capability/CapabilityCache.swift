import Foundation

/// Keeps the scanned capabilities on disk, keyed by OS build and hardware model, so a scan runs once per OS build.
nonisolated struct CapabilityCache: Sendable {
    static let fileName = "capabilities.json"

    let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    private var fileURL: URL { directory.appending(path: Self.fileName) }

    /// Nil when the file is missing, unreadable, was written for another OS build or model, or by an older scan.
    func load(osBuild: String, modelIdentifier: String) -> CaptureCapabilities? {
        guard let data = try? Data(contentsOf: fileURL),
              let capabilities = try? CaptureCapabilities.decode(data),
              capabilities.osBuild == osBuild, capabilities.modelIdentifier == modelIdentifier,
              capabilities.scanVersion == CaptureCapabilities.currentScanVersion
        else { return nil }
        return capabilities
    }

    /// Removes the cached file so the next load is a miss. A missing file is already clear.
    func clear() throws(CapabilityError) {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            throw .unwritable(path: fileURL.path, reason: String(describing: error))
        }
    }

    /// Creates the directory when it is missing.
    func save(_ capabilities: CaptureCapabilities) throws(CapabilityError) {
        let data = try capabilities.encoded()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw .unwritable(path: fileURL.path, reason: String(describing: error))
        }
    }
}
