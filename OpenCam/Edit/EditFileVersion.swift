import Foundation

/// Only the version of an edit or look file, so a file whose other keys this build does not know can still be told apart.
nonisolated struct EditFileVersion: Decodable, Sendable {
    let version: Int?

    /// The version a file's bytes declare, read without their shape (a missing version is 1); nil when the bytes are not a
    /// JSON object or the version is not a number.
    static func stored(in data: Data) -> Int? {
        (try? JSONDecoder().decode(EditFileVersion.self, from: data)).map { $0.version ?? 1 }
    }
}
