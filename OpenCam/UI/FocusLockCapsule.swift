import SwiftUI

/// "AE/AF lock", "AE lock" or "AF lock", in a glass capsule over the picture; the padding is `LibraryBadge`'s.
struct FocusLockCapsule: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.Text.caption)
            .lineLimit(1)
            .padding(.horizontal, Theme.Space.s)
            .padding(.vertical, Theme.Space.xs)
            .glassEffect(.regular, in: .capsule)
            .padding(Theme.Space.s)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
    }
}
