import SwiftUI

/// Round glass button for recording or taking a photo.
struct CaptureButton: View {
    let symbol: String
    let tint: Color
    var symbolColor: Color = .white
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(symbolColor)
                .frame(width: Theme.Size.captureButton, height: Theme.Size.captureButton)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .tint(tint)
        .accessibilityLabel(label)
    }
}
