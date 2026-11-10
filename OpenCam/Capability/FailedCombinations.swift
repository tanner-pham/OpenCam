import Foundation

/// The video options that failed the last format sweep of each lens, kept in `Application Support/OpenCam/failed-combinations.json`
/// for one OS build. They stay selectable; Record settings and the format summary only say so.
nonisolated struct FailedCombinations: Codable, Sendable, Equatable {
    static let fileName = "failed-combinations.json"
    static let caption = "This combination did not record in the last format sweep."

    var osBuild: String
    var failedByLens: [String: [VideoOption]]

    /// Empty, for `osBuild`, when the file is missing, unreadable or from another OS build.
    static func load(directory: URL, osBuild: String) -> FailedCombinations {
        let url = directory.appending(path: fileName, directoryHint: .notDirectory)
        guard let data = try? Data(contentsOf: url),
              let saved = try? JSONDecoder().decode(FailedCombinations.self, from: data),
              saved.osBuild == osBuild
        else { return FailedCombinations(osBuild: osBuild, failedByLens: [:]) }
        return saved
    }

    /// Creates the directory when it is missing.
    func save(directory: URL) throws(CapabilityError) {
        let url = directory.appending(path: Self.fileName, directoryHint: .notDirectory)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try encoder.encode(self).write(to: url, options: .atomic)
        } catch {
            throw .failedCombinationsUnwritable(path: url.path(percentEncoded: false), reason: String(describing: error))
        }
    }

    /// Replaces that lens's list only; an empty list removes the lens.
    func replacing(lensID: String, with failed: [VideoOption]) -> FailedCombinations {
        var copy = self
        copy.failedByLens[lensID] = failed.isEmpty ? nil : failed
        return copy
    }

    /// The caption when `option` failed the last sweep of its lens, else nil.
    func caption(for option: VideoOption?) -> String? {
        guard let option, failedByLens[option.lensID]?.contains(option) == true else { return nil }
        return Self.caption
    }
}
