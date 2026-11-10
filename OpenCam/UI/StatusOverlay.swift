import SwiftUI

/// The picture area's message when there is no picture, with Open Settings where Settings can fix it.
struct StatusOverlay: View {
    let status: ViewfinderStatus

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: Theme.Space.m) {
            Text(status.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if status.offersSettings {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .buttonStyle(.glass)
            }
        }
        .padding(.horizontal, Theme.Space.l)
    }
}
