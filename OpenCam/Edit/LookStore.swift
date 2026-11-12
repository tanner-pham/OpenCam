import Foundation
import OSLog

/// Looks as one JSON file each, named by the look's id, in one folder.
nonisolated struct LookStore: Sendable {
    static let maxNameLength = 40
    private static let logger = Logger(subsystem: "local.opencam.app", category: "LookStore")

    let directory: URL

    /// `Documents/Looks`, created if missing.
    static func appDefault() throws(LookStoreError) -> LookStore {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw .directoryUnavailable(reason: "No Documents folder")
        }
        return try LookStore(directory: documents.appending(path: "Looks", directoryHint: .isDirectory))
    }

    init(directory: URL) throws(LookStoreError) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw .directoryUnavailable(reason: error.localizedDescription)
        }
        self.directory = directory
    }

    /// By name (Finder-style), then creation date. Files that cannot be read are skipped and logged.
    func all() -> [Look] {
        let path = directory.path(percentEncoded: false)
        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: path)
        } catch {
            Self.logger.error("[LookStore:all] Cannot list looks — {path: \(path), reason: \(error.localizedDescription)}")
            return []
        }
        let looks = names.filter { $0.hasSuffix(".json") }.compactMap { name -> Look? in
            let url = directory.appending(path: name, directoryHint: .notDirectory)
            do {
                return try Self.decoder.decode(Look.self, from: Data(contentsOf: url))
            } catch {
                Self.logger.error("[LookStore:all] Skipped an unreadable look — {path: \(url.path(percentEncoded: false)), reason: \(error.localizedDescription)}")
                return nil
            }
        }
        return looks.sorted { a, b in
            switch a.name.localizedStandardCompare(b.name) {
            case .orderedAscending: true
            case .orderedDescending: false
            case .orderedSame: a.createdAt < b.createdAt
            }
        }
    }

    func save(name: String, adjustments: Adjustments, now: Date = .now) throws(LookStoreError) -> Look {
        let look = Look(id: UUID(), name: try Self.validName(name), adjustments: adjustments, createdAt: now)
        try write(look)
        return look
    }

    func rename(_ id: UUID, to name: String) throws(LookStoreError) -> Look {
        var look = try readWritable(id)
        look.name = try Self.validName(name)
        try write(look)
        return look
    }

    /// "<name> copy"; a long name is cut so the result still fits the limit.
    func duplicate(_ id: UUID, now: Date = .now) throws(LookStoreError) -> Look {
        let original = try readWritable(id)
        let suffix = " copy"
        let base = String(original.name.prefix(Self.maxNameLength - suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        return try save(name: base + suffix, adjustments: original.adjustments, now: now)
    }

    func delete(_ id: UUID) throws(LookStoreError) {
        let url = url(for: id)
        let path = url.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else { throw .notFound(id: id) }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            throw .unwritable(path: path, reason: error.localizedDescription)
        }
    }

    static func validName(_ raw: String) throws(LookStoreError) -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { throw .emptyName }
        if name.count > maxNameLength { throw .nameTooLong(count: name.count) }
        return name
    }

    static func nameProblem(_ raw: String) -> String? {
        do {
            _ = try validName(raw)
            return nil
        } catch {
            switch error {
            case .emptyName: return "Enter a name."
            case .nameTooLong: return "Use \(maxNameLength) characters or fewer."
            default: return nil
            }
        }
    }

    private func url(for id: UUID) -> URL {
        directory.appending(path: "\(id.uuidString).json", directoryHint: .notDirectory)
    }

    private func read(_ id: UUID) throws(LookStoreError) -> Look {
        let url = url(for: id)
        let path = url.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else { throw .notFound(id: id) }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw .unreadable(path: path, reason: error.localizedDescription)
        }
        do {
            return try Self.decoder.decode(Look.self, from: data)
        } catch {
            if let version = try? JSONDecoder().decode(EditFileVersion.self, from: data).version, version > Look.currentVersion {
                throw .newerVersion(path: path, version: version)
            }
            throw .unreadable(path: path, reason: error.localizedDescription)
        }
    }

    /// A look from a newer build is listed and can be deleted, but never rewritten, so its newer values survive.
    private func readWritable(_ id: UUID) throws(LookStoreError) -> Look {
        let look = try read(id)
        if look.version > Look.currentVersion {
            throw .newerVersion(path: url(for: id).path(percentEncoded: false), version: look.version)
        }
        return look
    }

    private func write(_ look: Look) throws(LookStoreError) {
        let url = url(for: look.id)
        var stamped = look
        stamped.version = Look.currentVersion
        do {
            try Self.encoder.encode(stamped).write(to: url, options: .atomic)
        } catch {
            throw .unwritable(path: url.path(percentEncoded: false), reason: error.localizedDescription)
        }
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
