import SwiftUI

/// Format summary that opens Record settings.
struct FormatButton: View {
    let parts: [String]
    var isStacked = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if isStacked {
                    VStack(spacing: 0) { ForEach(parts, id: \.self) { Text($0) } }
                } else {
                    Text(parts.joined(separator: "  "))
                }
            }
            .font(.footnote.weight(.semibold))
            .frame(minHeight: Theme.Size.formatLabel)
        }
        .buttonStyle(.glass)
        .controlSize(.regular)
        .fixedSize()
        .accessibilityLabel("Record settings, \(parts.joined(separator: ", "))")
    }
}
