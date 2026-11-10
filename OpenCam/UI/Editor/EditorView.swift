import SwiftUI

/// The editor: the photo beside or above the panel of sliders, with Done and Reset all in the toolbar.
struct EditorView: View {
    @Bindable var model: EditorModel
    let onDone: () -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var isConfirmingDiscard = false

    /// Stacked, the picture never takes so much height that less than this is left for the panel.
    private static let minPanelHeight: CGFloat = 240
    /// Until the proxy is decoded the picture keeps the camera's 4:3 shape.
    private static let defaultAspect: CGFloat = 4 / 3

    private var isFailed: Bool {
        if case .failed = model.phase { true } else { false }
    }

    var body: some View {
        layout
            .navigationTitle(model.item.stem)
            .navigationBarTitleDisplayMode(.inline)
            // SwiftUI cannot ask before the system back control or swipe pops, so both are replaced by a system cancel
            // button that asks first when changes would be lost. Hiding the back control also turns off the back swipe.
            .navigationBarBackButtonHidden()
            .toolbar { toolbar }
            .confirmationDialog("Discard changes?", isPresented: $isConfirmingDiscard, titleVisibility: .visible) {
                Button("Discard changes", role: .destructive, action: onDone)
                Button("Keep editing", role: .cancel) {}
            }
            .task {
                guard model.phase == .loading else { return }
                await model.load()
            }
    }

    @ViewBuilder
    private var layout: some View {
        switch EditorLayout.choose(horizontal: horizontalSizeClass, vertical: verticalSizeClass) {
        case .sideBySide:
            HStack(spacing: 0) {
                EditorPicture(model: model)
                EditorPanel(model: model)
                    .frame(width: EditorLayout.panelWidth)
                    .disabled(isFailed)
            }
        case .stacked:
            GeometryReader { geo in
                VStack(spacing: 0) {
                    EditorPicture(model: model)
                        .frame(height: pictureHeight(in: geo.size))
                    EditorPanel(model: model)
                        .disabled(isFailed)
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(role: .cancel, action: leave)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button("Reset all", action: model.resetAll)
                .disabled(isFailed || (model.adjustments.isIdentity && model.lookName == nil))
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Done", action: done)
        }
    }

    /// A failed photo closes without saving, so it never traps the person; otherwise the edit is saved first.
    private func done() {
        if isFailed || model.save() { onDone() }
    }

    /// Leaves without saving, asking first when changes would be lost.
    private func leave() {
        if model.hasUnsavedChanges { isConfirmingDiscard = true } else { onDone() }
    }

    /// The picture's fitted height at the full width, held so the panel keeps `minPanelHeight`.
    private func pictureHeight(in size: CGSize) -> CGFloat {
        let aspect = model.proxySize.map { $0.width / max($0.height, 1) } ?? Self.defaultAspect
        let fitted = size.width / aspect
        return max(0, min(fitted, size.height - Self.minPanelHeight))
    }
}
