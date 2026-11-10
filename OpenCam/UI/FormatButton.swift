import SwiftUI

/// Format summary that opens Record settings. With `onLongPress` (video mode), a long press offers the format sweep;
/// the system menu keeps a tap and a long press apart. `isWarning` uses the remaining-time warning colour.
struct FormatButton: View {
    let parts: [String]
    var isStacked = false
    var isWarning = false
    var onLongPress: (() -> Void)?
    let action: () -> Void

    var body: some View {
        Group {
            if let onLongPress {
                Menu {
                    Button("Format sweep", systemImage: "checklist", action: onLongPress)
                } label: {
                    label
                } primaryAction: {
                    action()
                }
            } else {
                Button(action: action) { label }
            }
        }
        .buttonStyle(.glass)
        .controlSize(.regular)
        .fixedSize()
        .accessibilityLabel(accessibilityText)
    }

    private var label: some View {
        Group {
            if isStacked {
                VStack(spacing: 0) { ForEach(parts, id: \.self) { Text($0) } }
            } else {
                Text(parts.joined(separator: "  "))
            }
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(isWarning ? AnyShapeStyle(Theme.recordRed) : AnyShapeStyle(.foreground))
        .frame(minHeight: Theme.Size.formatLabel)
    }

    private var accessibilityText: String {
        let base = "Record settings, \(parts.joined(separator: ", "))"
        return isWarning ? "\(base). \(FailedCombinations.caption)" : base
    }
}
