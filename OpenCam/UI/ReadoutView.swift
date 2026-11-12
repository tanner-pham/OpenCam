import SwiftUI

/// A small uppercase caption over a monospaced value. `isSet` draws the value in the accent (set by hand) and `isOpen`
/// draws a short accent bar under it (its slider is open); neither changes the readout's size.
struct ReadoutView: View {
    let caption: String
    let value: String
    var isAlert = false
    var showsIndicator = false
    var isCompact = false
    var isSet = false
    var isOpen = false

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
                    .foregroundStyle(isAlert ? Theme.recordRed : isSet ? Theme.accent : .primary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, isCompact ? 0 : Theme.Space.s)
        .frame(maxWidth: .infinity, minHeight: Theme.Size.minTarget)
        .overlay(alignment: .bottom) {
            if isOpen {
                Capsule().fill(Theme.accent).frame(width: Theme.Space.l, height: 2).padding(.bottom, Theme.Space.xs)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(caption) \(value)")
    }
}
