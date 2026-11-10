import Foundation
import UniformTypeIdentifiers

/// One picture the person chose to import: its bytes and the type the picker reported for them.
nonisolated struct ImportCandidate: Sendable {
    let data: Data
    let contentType: UTType
}
