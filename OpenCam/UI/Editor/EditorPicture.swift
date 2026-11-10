import SwiftUI

/// The photo with its edit, or without it while held; a sentence instead when the photo cannot be shown.
struct EditorPicture: View {
    @Bindable var model: EditorModel

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, Theme.Space.s)
    }

    @ViewBuilder
    private var content: some View {
        if case .failed(let message) = model.phase {
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(Theme.Space.l)
        } else if let image = model.isShowingOriginal ? model.original : model.preview {
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFit()
                .overlay(alignment: .top) { originalBadge }
                .onLongPressGesture(minimumDuration: 0.15, perform: {}, onPressingChanged: { model.isShowingOriginal = $0 })
                .accessibilityElement()
                .accessibilityLabel(model.item.stem)
        } else {
            ProgressView()
        }
    }

    @ViewBuilder
    private var originalBadge: some View {
        if model.isShowingOriginal {
            Text("Original")
                .font(.subheadline)
                .padding(.horizontal, Theme.Space.m)
                .padding(.vertical, Theme.Space.xs)
                .glassEffect(.regular, in: .capsule)
                .padding(Theme.Space.s)
        }
    }
}
