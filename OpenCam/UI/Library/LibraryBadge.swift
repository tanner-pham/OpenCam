import SwiftUI

/// A small glass capsule on a library cell's corner: the clip's duration or the photo's format.
struct LibraryBadge<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .font(.caption)
            .padding(.horizontal, Theme.Space.s)
            .padding(.vertical, Theme.Space.xs)
            .glassEffect(.regular, in: .capsule)
            .padding(Theme.Space.s)
    }
}
