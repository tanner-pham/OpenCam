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
        recentCaptures(limit: 1).first
    }

    /// The newest `limit` captures, newest first, one per number; empty when there is none or the folder cannot be read.
    /// Lists the folder's names only: no file is opened.
    func recentCaptures(limit: Int) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))) ?? []
        return Self.recentCaptureNames(names, limit: limit).map { directory.appending(path: $0, directoryHint: .notDirectory) }
    }

    /// The photo or clip with the highest number; within one number HEIC comes first, then JPG (imports and Simulator
    /// samples), PNG, MOV and DNG. Sidecars, edit files and every other file, such as a sweep's report, are never offered.
    static func latestCaptureName(_ names: [String]) -> String? {
        recentCaptureNames(names, limit: 1).first
    }

    /// The `limit` highest numbers, highest first, each by its file `latestCaptureName` would pick for that number.
    static func recentCaptureNames(_ names: [String], limit: Int) -> [String] {
        let kinds: [CaptureFileKind] = [.heic, .jpg, .png, .mov, .dng]
        var best: [Int: (rank: Int, name: String)] = [:]
        for name in names {
            guard let dot = name.firstIndex(of: "."), let sequence = number(of: name) else { continue }
            let fileExtension = name[name.index(after: dot)...].uppercased()
            guard let rank = kinds.firstIndex(where: { $0.rawValue == fileExtension }) else { continue }
            if let current = best[sequence], current.rank <= rank { continue }
            best[sequence] = (rank, name)
        }
        return best.keys.sorted(by: >).prefix(limit).compactMap { best[$0]?.name }
    }

    /// One above the highest number among `OC_<digits>.<extension>` names, edit files included; 1 when there is none.
    static func nextSequence(existingNames: [String]) -> Int {
        (existingNames.compactMap(number(of:)).max() ?? 0) + 1
    }

    /// The `OC_` number of a file name with an extension, read from its stem (the name up to the first dot) by the
    /// Library's parser, so capture numbering and the Library agree.
    private static func number(of name: String) -> Int? {
        guard let dot = name.firstIndex(of: ".") else { return nil }
        return LibraryScanner.sequence(ofStem: String(name[..<dot]))
    }
}
