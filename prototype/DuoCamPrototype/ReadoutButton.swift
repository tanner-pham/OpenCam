import SwiftUI

/// A small uppercase caption over a monospaced value. Selected readouts sit on tinted glass.
struct ReadoutButton: View {
    let caption: String
    let value: String
    var isSelected = false
    var isAlert = false
    var showsIndicator = false
    var isCompact = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
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
                        .foregroundStyle(isAlert ? Theme.recordRed : (isSelected ? Theme.accent : .primary))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, isCompact ? 0 : Theme.Space.s)
            .frame(maxWidth: .infinity, minHeight: Theme.Size.minTarget)
            .contentShape(.rect)
            .modifier(SelectedGlass(isSelected: isSelected))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(caption) \(value)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct SelectedGlass: ViewModifier {
    let isSelected: Bool

    func body(content: Content) -> some View {
        if isSelected {
            content.glassEffect(.regular.tint(Theme.accent.opacity(0.3)), in: .rect(cornerRadius: Theme.Space.m))
        } else {
            content
        }
    }
}
