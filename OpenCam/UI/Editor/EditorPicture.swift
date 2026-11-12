import SwiftUI

/// The photo with its edit, or without it while held; a sentence instead when the photo cannot be shown.
struct EditorPicture: View {
    @Bindable var model: EditorModel

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                // Before the overlays, so a touch on a mask handle is the handle's alone and never a press on the picture.
                .onLongPressGesture(minimumDuration: 0.15, perform: {}, onPressingChanged: { model.isShowingOriginal = $0 })
                .overlay { maskLayers }
                .overlay(alignment: .top) { originalBadge }
                .accessibilityElement()
                .accessibilityLabel(model.item.stem)
        } else {
            ProgressView()
        }
    }

    /// The selected mask in red and its handles, only in the Masks group and never over the original.
    @ViewBuilder
    private var maskLayers: some View {
        if model.group == .masks {
            ZStack {
                if model.isShowingMaskOverlay, let overlay = model.maskOverlay {
                    Image(decorative: overlay, scale: 1)
                        .resizable()
                        .allowsHitTesting(false)
                }
                if let kind = model.selectedMask?.shape.kind, kind == .linear || kind == .radial {
                    MaskHandles(model: model)
                }
            }
            // Kept in the tree, only hidden, so a press on the picture never removes a handle mid-touch.
            .opacity(model.isShowingOriginal ? 0 : 1)
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
