import Foundation

/// The camera's logged errors, also kept in `Documents/opencam-errors.log`. A sideloaded build has no crash reporter and
/// the system log can only be read while a Mac is attached, so this is how a failure on the phone is read afterwards.
nonisolated struct ErrorJournal: Sendable {
    static let fileName = "opencam-errors.log"
    /// When the file passes this size its older half is dropped.
    static let maxBytes = 200_000

    let fileURL: URL

    private static let queue = DispatchQueue(label: "opencam.error-journal")

    /// Appends one timestamped line to the app's journal, off the caller's thread. Never throws: a journal that cannot
    /// be written must not make the failure it records worse.
    static func record(_ message: String) {
        let line = "\(Date.now.ISO8601Format()) \(message)"
        queue.async {
            guard let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
            ErrorJournal(fileURL: directory.appending(path: fileName)).append(line)
        }
    }

    func append(_ line: String) {
        var data = (try? Data(contentsOf: fileURL)) ?? Data()
        data.append(Data((line + "\n").utf8))
        if data.count > Self.maxBytes {
            // Keep the newer half, from the start of a line.
            let tail = data.suffix(Self.maxBytes / 2)
            data = tail.firstIndex(of: UInt8(ascii: "\n")).map { Data(tail.suffix(from: tail.index(after: $0))) } ?? Data(tail)
        }
        try? data.write(to: fileURL, options: .atomic)
    }
}
