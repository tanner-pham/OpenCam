import Foundation

/// One line of the editor's "Photo info" popover.
nonisolated struct PhotoInfoRow: Sendable, Equatable {
    let title: String
    let value: String
}
