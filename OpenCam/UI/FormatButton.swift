import SwiftUI

/// The lines the format summary is drawn in, from the shortest to the tallest.
nonisolated enum SummaryForm: Equatable, Sendable {
    /// Every part on one line.
    case oneLine
    /// The format on one line and the look, when there is one, on a second.
    case formatAndLook
    /// One part per line, the last resort.
    case onePerLine

    /// `parts` are the format's parts, then the look's name when `hasLook`.
    func lines(parts: [String], hasLook: Bool) -> [String] {
        switch self {
        case .oneLine:
            return [parts.joined(separator: "  ")]
        case .formatAndLook:
            guard hasLook, parts.count > 1, let look = parts.last else { return [parts.joined(separator: "  ")] }
            return [parts.dropLast().joined(separator: "  "), look]
        case .onePerLine:
            return parts
        }
    }
}

/// Format summary that opens Record settings. With `onLongPress` (video mode), a long press offers the format sweep;
/// the system menu keeps a tap and a long press apart; a `.disabled` button disables both and draws dimmed. `isWarning`
/// draws the button in the warning colour, filled, so its text stays readable over a picture.
struct FormatButton: View {
    let parts: [String]
    var form = SummaryForm.oneLine
    /// The last of `parts` is a look's name.
    var hasLook = false
    var isWarning = false
    var onLongPress: (() -> Void)?
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Group {
            if isWarning {
                button.buttonStyle(.glassProminent).tint(Theme.recordRed)
            } else {
                button.buttonStyle(.glass)
            }
        }
        .controlSize(.regular)
        .fixedSize()
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder private var button: some View {
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

    private var label: some View {
        VStack(spacing: 0) {
            ForEach(Array(form.lines(parts: parts, hasLook: hasLook).enumerated()), id: \.offset) { Text($0.element) }
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(isWarning ? AnyShapeStyle(.white) : AnyShapeStyle(.foreground))
        .frame(minHeight: Theme.Size.formatLabel)
        // An explicit foreground style stops the system dimming a disabled glass button, so the label dims itself, as the
        // readouts do.
        .opacity(isEnabled ? 1 : 0.4)
    }

    private var accessibilityText: String {
        let base = "Record settings, \(parts.joined(separator: ", "))"
        return isWarning ? "\(base). \(FailedCombinations.caption)" : base
    }
}
