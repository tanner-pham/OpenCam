import SwiftUI

/// The one line of status under the controls. The microphone line is a button that opens Settings.
struct NoticeLine: View {
    let model: CameraModel
    /// On glass over the picture the text is primary, for contrast.
    var isOnGlass = false

    @Environment(\.openURL) private var openURL

    var body: some View {
        if let text = model.bottomNotice {
            if model.bottomNoticeOpensSettings {
                Button { openSettings() } label: { line(text) }
                    .buttonStyle(.plain)
            } else {
                line(text)
            }
        }
    }

    private func line(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(isOnGlass ? .primary : .secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }
}
