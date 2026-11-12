import Foundation

/// One line of the editor's "Photo info" sheet.
nonisolated struct PhotoInfoRow: Sendable, Equatable {
    let title: String
    let value: String
}
