import SwiftUI

/// A small uppercase caption over a monospaced value. Read-only.
struct ReadoutView: View {
    let caption: String
    let value: String
    var isAlert = false
    var showsIndicator = false
    var isCompact = false

    var body: some View {
        VStack(spacing: 2) {
            Text(caption)
                .font(isCompact ? Theme.Text.compactCaption : Theme.Text.caption)
                .tracking(0.4)
                .foregroundStyle(.secondary)
            HStack(spacing: Theme.Space.xs) {
                if showsIndicator {
                    Circle().fill(Theme.recordRed).frame(width: Theme.Space.s, height: Theme.Space.s)
                }
                Text(value)
                    .font(isCompact ? Theme.Text.compactValue : Theme.Text.value)
                    .foregroundStyle(isAlert ? Theme.recordRed : .primary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, isCompact ? 0 : Theme.Space.s)
        .frame(maxWidth: .infinity, minHeight: Theme.Size.minTarget)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(caption) \(value)")
    }
}
