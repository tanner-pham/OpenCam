import OSLog
import SwiftUI

/// The Looks group: "None" and every saved look as tiles of this photo, a tap applies one; "Save as look" under the grid.
/// Each look tile's context menu renames, duplicates or deletes it.
struct LooksPanel: View {
    @Bindable var model: EditorModel

    private static let logger = Logger(subsystem: "local.opencam.app", category: "LooksPanel")
    private static let columns = [GridItem(.adaptive(minimum: 96), spacing: Theme.Space.m)]
    private static let saveFailed = "The look could not be saved."
    private static let newerLook = "This look was made by a newer version of OpenCam, so it can't be changed here."
    private static let deleteFailed = "The look could not be deleted."

    /// Rendered tiles by the adjustments they show.
    @State private var images: [Adjustments: CGImage] = [:]
    @State private var naming: LookNaming?
    @State private var deleting: Look?
    @State private var failure: String?

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Space.l) {
                LazyVGrid(columns: Self.columns, spacing: Theme.Space.m) {
                    tile(for: nil)
                    ForEach(model.looks) { look in
                        tile(for: look)
                            .contextMenu { menu(for: look) }
                    }
                }
                Button("Save as look", action: startNamingNew)
                    .buttonStyle(.bordered)
                    .disabled(model.adjustments.isIdentity)
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.top, Theme.Space.m)
            .padding(.bottom, Theme.Space.l)
        }
        .scrollBounceBehavior(.basedOnSize)
        // The Save action gets the value the sheet was presented with, so dismissal clearing `naming` cannot turn a rename
        // into a new look.
        .sheet(item: $naming) { presented in
            LookNameSheet(naming: presented) { saveName($0, for: presented) }
        }
        .confirmationDialog(deleting.map { "Delete \u{201C}\($0.name)\u{201D}?" } ?? "", isPresented: isDeleting,
                            titleVisibility: .visible, presenting: deleting) { look in
            Button("Delete", role: .destructive) { delete(look) }
        } message: { _ in
            Text("Photos that used it keep their edits.")
        }
        .alert(failure ?? "", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK") {}
        }
    }

    /// Nil is "None". The picture is requested once the photo is loaded, and again only when the look's values change.
    private func tile(for look: Look?) -> some View {
        let values = look?.adjustments ?? Adjustments()
        let isReady = model.phase == .ready
        return Button {
            model.applyLook(look)
        } label: {
            let isSelected = LookSelection.isSelected(look, among: model.looks, for: model.adjustments, lookName: model.lookName)
            LookTile(title: look?.name ?? "None", image: images[values], isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .task(id: isReady ? values : nil) {
            guard isReady, images[values] == nil, let image = await model.lookPreview(look) else { return }
            images[values] = image
        }
    }

    @ViewBuilder
    private func menu(for look: Look) -> some View {
        // The header shows the whole name, which the tile may end with an ellipsis.
        Section(look.name) {
            Button("Rename", systemImage: "pencil") { startRenaming(look) }
            Button("Duplicate", systemImage: "plus.square.on.square") { duplicate(look) }
            Button("Delete", systemImage: "trash", role: .destructive) { deleting = look }
        }
    }

    private var isDeleting: Binding<Bool> {
        Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
    }

    private func startNamingNew() {
        naming = .new
    }

    private func startRenaming(_ look: Look) {
        naming = .rename(look)
    }

    /// Save stays unavailable while the name has a problem, so only a store failure reaches the catch.
    private func saveName(_ name: String, for presented: LookNaming) {
        do throws(LookStoreError) {
            try model.saveLookName(name, renaming: presented.look)
        } catch {
            Self.logger.error("\(error.description, privacy: .public)")
            failure = Self.saveFailure(for: error)
        }
    }

    private func duplicate(_ look: Look) {
        do throws(LookStoreError) {
            try model.duplicateLook(look.id)
        } catch {
            Self.logger.error("\(error.description, privacy: .public)")
            failure = Self.saveFailure(for: error)
        }
    }

    /// A look from a newer build is never rewritten, so rename and duplicate say why instead of only that they failed.
    private static func saveFailure(for error: LookStoreError) -> String {
        if case .newerVersion = error { newerLook } else { saveFailed }
    }

    private func delete(_ look: Look) {
        do throws(LookStoreError) {
            try model.deleteLook(look.id)
        } catch {
            Self.logger.error("\(error.description, privacy: .public)")
            failure = Self.deleteFailed
        }
    }
}
