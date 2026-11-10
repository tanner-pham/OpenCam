import Foundation

/// Only the version of an edit file, so a file whose other keys this build does not know can still be told apart.
nonisolated struct EditFileVersion: Decodable, Sendable {
    let version: Int?
}
