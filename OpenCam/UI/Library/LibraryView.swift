import PhotosUI
import QuickLook
import SwiftUI

/// Everything in the Captures folder as a grid, drawn with each photo's edit.
struct LibraryView: View {
    let library: LibraryStore
    let launch: LaunchConfig

    @Environment(\.dismiss) private var dismiss
    @State private var path: [LibraryItem] = []
    @State private var isSelecting: Bool
    @State private var selectedIDs: Set<String> = []
    @State private var hasAppliedLaunch = false
    @State private var previewURL: URL?
    @State private var isConfirmingDelete = false
    @State private var alertTitle: String?
    @State private var pickedItems: [PhotosPickerItem] = []
    /// The group the next editor opens on: `-editorGroup` for the launch push, Light for a tap.
    @State private var editorGroup: EditorGroup = .light

    private static let columns = [GridItem(.adaptive(minimum: 110), spacing: 2)]

    init(library: LibraryStore, launch: LaunchConfig) {
        self.library = library
        self.launch = launch
        _isSelecting = State(initialValue: launch.startsInSelectMode)
    }

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle(isSelecting ? LibraryCopy.selectionTitle(count: selectedIDs.count) : LibraryCopy.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
                .navigationDestination(for: LibraryItem.self) { item in
                    EditorScreen(item: item, library: library, group: editorGroup) { path.removeAll() }
                }
        }
        .tint(Theme.accent)
        .onAppear {
            library.reload()
            applyLaunch()
        }
        .onChange(of: path) { old, new in
            // Back from the editor: its saved edit changes the thumbnail key, so the cell renders again.
            guard new.count < old.count else { return }
            library.reload()
        }
        .onChange(of: pickedItems) { _, items in importPicked(items) }
        .quickLookPreview($previewURL)
        .confirmationDialog(LibraryCopy.deleteTitle(count: selectedIDs.count), isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: deleteSelected)
        } message: {
            Text(LibraryCopy.deleteMessage)
        }
        .alert(alertTitle ?? "", isPresented: Binding(get: { alertTitle != nil }, set: { if !$0 { alertTitle = nil } })) {
            Button("OK") {}
        }
    }

    @ViewBuilder
    private var content: some View {
        if library.items.isEmpty {
            ContentUnavailableView(LibraryCopy.emptyTitle, systemImage: "photo.on.rectangle", description: Text(LibraryCopy.emptyDetail))
        } else {
            ScrollView {
                LazyVGrid(columns: Self.columns, spacing: 2) {
                    ForEach(library.items) { item in
                        Button { tap(item) } label: {
                            LibraryCell(library: library, item: item, isSelecting: isSelecting, isSelected: selectedIDs.contains(item.id))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(role: .close) { dismiss() }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            if !isSelecting {
                PhotosPicker(selection: $pickedItems, maxSelectionCount: nil, selectionBehavior: .ordered, matching: .images, preferredItemEncoding: .current) {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
            }
            Button(isSelecting ? "Done" : "Select") { setSelecting(!isSelecting) }
                .disabled(library.items.isEmpty && !isSelecting)
        }
        if isSelecting {
            LibrarySelectionBar(count: selectedIDs.count, looks: library.looks, onApply: applyLook, onRemoveLook: removeLook) {
                isConfirmingDelete = true
            }
        }
    }

    /// Loads what the picker returned, imports it, empties the selection and tells the person what happened.
    private func importPicked(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        pickedItems = []
        Task {
            var candidates: [ImportCandidate] = []
            var unloaded = 0
            for item in items {
                if let candidate = await PhotoImporter.candidate(from: item) { candidates.append(candidate) } else { unloaded += 1 }
            }
            let result = await library.importPhotos(candidates)
            alertTitle = ImportResult(imported: result.imported, failed: result.failed + unloaded).message
        }
    }

    private func tap(_ item: LibraryItem) {
        if isSelecting {
            if selectedIDs.contains(item.id) { selectedIDs.remove(item.id) } else { selectedIDs.insert(item.id) }
        } else if item.kind == .clip {
            previewURL = item.pictureURL
        } else {
            openEditor(item, group: .light)
        }
    }

    /// Only photos reach the editor.
    private func openEditor(_ item: LibraryItem, group: EditorGroup) {
        guard item.isEditable else { return }
        editorGroup = group
        path = [item]
    }

    private func setSelecting(_ isOn: Bool) {
        isSelecting = isOn
        selectedIDs = []
    }

    /// Once, after the items have loaded: `-librarySelect on` opens in Select mode with the newest item selected, and
    /// `-screen editor` opens the newest photo in the editor on the `-editorGroup` group.
    private func applyLaunch() {
        guard !hasAppliedLaunch else { return }
        hasAppliedLaunch = true
        if launch.startsInSelectMode, let first = library.items.first {
            selectedIDs = [first.id]
        }
        if launch.screen == .editor, let photo = library.items.first(where: \.isEditable) {
            openEditor(photo, group: launch.editorGroup)
        }
    }

    private func applyLook(_ look: Look) {
        changeLook { () throws(LibraryError) in try library.applyLook(look, to: selectedItems) }
    }

    private func removeLook() {
        changeLook { () throws(LibraryError) in try library.removeLook(from: selectedItems) }
    }

    /// The store reloads, so the grid redraws with the new edits; the selection stays for another change.
    private func changeLook(_ change: () throws(LibraryError) -> LookChange) {
        do throws(LibraryError) {
            alertTitle = try change().message
        } catch {
            // The store has logged each cause; the person sees a fixed sentence.
            alertTitle = LibraryCopy.saveFailed
        }
    }

    private var selectedItems: [LibraryItem] {
        library.items.filter { selectedIDs.contains($0.id) }
    }

    private func deleteSelected() {
        let doomed = library.items.filter { selectedIDs.contains($0.id) }
        do throws(LibraryError) {
            try library.delete(doomed)
            setSelecting(false)
        } catch {
            // The store has logged the cause; the person sees a fixed sentence.
            if case .newerEdit = error { alertTitle = LibraryCopy.newerEdit } else { alertTitle = LibraryCopy.deleteFailed }
            let remaining = Set(library.items.map(\.id))
            selectedIDs.formIntersection(remaining)
        }
    }
}
