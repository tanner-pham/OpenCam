import PhotosUI
import OSLog
import QuickLook
import SwiftUI

/// Everything in the Captures folder as a grid, drawn with each photo's edit.
struct LibraryView: View {
    let library: LibraryStore
    let launch: LaunchConfig

    private static let logger = Logger(subsystem: "local.opencam.app", category: "LibraryView")
    @Environment(\.dismiss) private var dismiss
    @State private var path: [LibraryItem] = []
    @State private var isSelecting: Bool
    @State private var selectedIDs: Set<String> = []
    @State private var hasAppliedLaunch = false
    @State private var previewURL: URL?
    @State private var isConfirmingDelete = false
    @State private var alertTitle: String?
    /// The look waiting for "Replace edits on N photos?", and N when it was asked.
    @State private var replacingLook: Look?
    @State private var replaceCount = 0
    @State private var isConfirmingRemove = false
    @State private var removeCount = 0
    @State private var pickedItems: [PhotosPickerItem] = []
    /// The group the next editor opens on: `-editorGroup` for the launch push, Light for a tap.
    @State private var editorGroup: EditorGroup = .light
    /// The look the next editor applies, unsaved: `-editorLook` for the launch push, nil for a tap.
    @State private var editorLookName: String?

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
                    EditorScreen(item: item, library: library, group: editorGroup, lookName: editorLookName) { path.removeAll() }
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
        .confirmationDialog(LibraryCopy.removeLookTitle(count: removeCount), isPresented: $isConfirmingRemove, titleVisibility: .visible) {
            Button("Remove look", role: .destructive, action: removeLook)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(LibraryCopy.removeLookMessage)
        }
        // The Apply action gets the look the dialog was presented with, never state the dismissal clears.
        .confirmationDialog(LibraryCopy.replaceEditsTitle(count: replaceCount),
                            isPresented: Binding(get: { replacingLook != nil }, set: { if !$0 { replacingLook = nil } }),
                            titleVisibility: .visible, presenting: replacingLook) { look in
            Button("Apply look") { applyLook(look) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text(LibraryCopy.replaceEditsMessage)
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
            LibrarySelectionBar(count: selectedIDs.count, looks: library.looks, onApply: requestApply, onRemoveLook: requestRemove) {
                isConfirmingDelete = true
            }
        }
    }

    /// Imports what the picker returned one picture at a time, empties the selection and tells the person what happened.
    private func importPicked(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        pickedItems = []
        Task {
            let result = await library.importPhotos(items, load: PhotoImporter.candidate(from:))
            alertTitle = result.message
        }
    }

    private func tap(_ item: LibraryItem) {
        if isSelecting {
            if selectedIDs.contains(item.id) { selectedIDs.remove(item.id) } else { selectedIDs.insert(item.id) }
        } else if item.kind == .clip {
            previewURL = item.pictureURL
        } else {
            openEditor(item, group: .light, lookName: nil)
        }
    }

    /// Only photos reach the editor.
    private func openEditor(_ item: LibraryItem, group: EditorGroup, lookName: String?) {
        guard item.isEditable else { return }
        editorGroup = group
        editorLookName = lookName
        path = [item]
    }

    private func setSelecting(_ isOn: Bool) {
        isSelecting = isOn
        selectedIDs = []
    }

    /// Once, after the items have loaded: in the Simulator `-seedFormats on` and `-seedStudy on` seed first, then the store
    /// reloads once; `-librarySelect on` opens in Select mode with the newest item selected, and `-screen editor` opens the
    /// newest photo in the editor on the `-editorGroup` group, applying the `-editorLook` look.
    private func applyLaunch() {
        guard !hasAppliedLaunch else { return }
        hasAppliedLaunch = true
        #if targetEnvironment(simulator)
        if launch.seedsFormats {
            do throws(LibraryError) {
                _ = try SampleSeeder.seedFormatsIfAbsent(library.captures)
            } catch {
                Self.logger.error("\(error.description, privacy: .public)")
            }
        }
        if launch.seedsStudyLook {
            do throws(LookStoreError) {
                _ = try LookSeeder.seedColourStudy(into: library.lookStore)
            } catch {
                Self.logger.error("\(error.description, privacy: .public)")
            }
        }
        if launch.seedsFormats || launch.seedsStudyLook {
            library.reload()
        }
        #endif
        if launch.startsInSelectMode, let first = library.items.first {
            selectedIDs = [first.id]
        }
        if launch.screen == .editor, let photo = library.items.first(where: \.isEditable) {
            openEditor(photo, group: launch.editorGroup, lookName: launch.editorLookName)
        }
    }

    /// Applies at once unless it would replace edits the photos already have; then it asks first.
    private func requestApply(_ look: Look) {
        let count = LookChange.editsToReplace(in: library.lookEdits(for: selectedItems))
        guard count > 0 else { return applyLook(look) }
        replaceCount = count
        replacingLook = look
    }

    /// Asks first when any photo would change; with none there is nothing to confirm and the result says so.
    private func requestRemove() {
        let count = LookChange.photosToRemove(in: library.lookEdits(for: selectedItems))
        guard count > 0 else { return removeLook() }
        removeCount = count
        isConfirmingRemove = true
    }

    private func applyLook(_ look: Look) {
        changeLook { () throws(LibraryError) in try library.applyLook(look, to: selectedItems) }
    }

    private func removeLook() {
        changeLook { () throws(LibraryError) in try library.removeLook(from: selectedItems) }
    }

    /// The store reloads, so the grid redraws with the new edits; the selection stays for another change. When some photos
    /// could not be changed the result still says what happened to every item.
    private func changeLook(_ change: () throws(LibraryError) -> LookChange) {
        do throws(LibraryError) {
            alertTitle = try change().message
        } catch {
            // The store has logged each cause.
            if case .lookChangeIncomplete(let result, _) = error { alertTitle = result.message } else { alertTitle = LibraryCopy.saveFailed }
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
            switch error {
            case .newerEdit: alertTitle = LibraryCopy.newerEdit
            case .unreadableEdit: alertTitle = LibraryCopy.unreadableEdit
            default: alertTitle = LibraryCopy.deleteFailed
            }
            let remaining = Set(library.items.map(\.id))
            selectedIDs.formIntersection(remaining)
        }
    }
}
