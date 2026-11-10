import Foundation

/// Names and numbers capture files in one folder. A number is handed out once per run and starts above every
/// number already in the folder, so no capture overwrites another.
final class CaptureStore {
    let directory: URL
    private var next: Int

    /// `Documents/Captures`, created if missing.
    static func appDefault() throws(CaptureStoreError) -> CaptureStore {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw .documentsMissing
        }
        return try CaptureStore(directory: documents.appending(path: "Captures", directoryHint: .isDirectory))
    }

    init(directory: URL) throws(CaptureStoreError) {
        let manager = FileManager.default
        let path = directory.path(percentEncoded: false)
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw .cannotCreateDirectory(path: path, reason: error.localizedDescription)
        }
        let names: [String]
        do {
            names = try manager.contentsOfDirectory(atPath: path)
        } catch {
            throw .cannotReadDirectory(path: path, reason: error.localizedDescription)
        }
        self.directory = directory
        self.next = Self.nextSequence(existingNames: names)
    }

    /// Never returns the same number twice in this run.
    func reserveSequence() -> Int {
        defer { next += 1 }
        return next
    }

    func url(sequence: Int, kind: CaptureFileKind) -> URL {
        directory.appending(path: Self.fileName(sequence: sequence, kind: kind), directoryHint: .notDirectory)
    }

    /// What identifies a capture file when matching it: its name, which is unique in the one captures folder. A system
    /// callback may report the same file as `/private/var/…` where it was given `/var/…`, so whole URLs are never compared.
    nonisolated static func clipKey(for url: URL) -> String {
        url.lastPathComponent
    }

    /// "OC_0001.DNG": the number padded to four digits, wider when it needs more.
    static func fileName(sequence: Int, kind: CaptureFileKind) -> String {
        let digits = String(sequence)
        return "OC_" + String(repeating: "0", count: max(0, 4 - digits.count)) + digits + "." + kind.rawValue
    }

    /// The newest capture in the folder, or nil when there is none or the folder cannot be read.
    func latestCapture() -> URL? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))) ?? []
        return Self.latestCaptureName(names).map { directory.appending(path: $0, directoryHint: .notDirectory) }
    }

    /// The photo or clip with the highest number; within one number HEIC comes first, then MOV, then DNG.
    /// Sidecars and every other file, such as a sweep's report, are never offered.
    static func latestCaptureName(_ names: [String]) -> String? {
        let kinds: [CaptureFileKind] = [.heic, .mov, .dng]
        let candidates = names.compactMap { name -> (sequence: Int, rank: Int, name: String)? in
            guard name.hasPrefix("OC_"), let dot = name.firstIndex(of: ".") else { return nil }
            let stem = name[name.index(name.startIndex, offsetBy: 3)..<dot]
            guard !stem.isEmpty, stem.allSatisfy({ $0.isASCII && $0.isNumber }), let sequence = Int(stem) else { return nil }
            let fileExtension = name[name.index(after: dot)...].uppercased()
            guard let rank = kinds.firstIndex(where: { $0.rawValue == fileExtension }) else { return nil }
            return (sequence, rank, name)
        }
        return candidates.max { ($0.sequence, -$0.rank) < ($1.sequence, -$1.rank) }?.name
    }

    /// One above the highest number among `OC_<digits>.<extension>` names; 1 when there is none.
    static func nextSequence(existingNames: [String]) -> Int {
        let numbers = existingNames.compactMap { name -> Int? in
            guard name.hasPrefix("OC_"), let dot = name.firstIndex(of: ".") else { return nil }
            let stem = name[name.index(name.startIndex, offsetBy: 3)..<dot]
            guard !stem.isEmpty, stem.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
            return Int(stem)
        }
        return (numbers.max() ?? 0) + 1
    }
}
