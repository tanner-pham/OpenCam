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
        }
        .tint(Theme.accent)
        .onAppear {
            library.reload()
            applyLaunchSelection()
        }
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
        ToolbarItem(placement: .topBarTrailing) {
            Button(isSelecting ? "Done" : "Select") { setSelecting(!isSelecting) }
                .disabled(library.items.isEmpty && !isSelecting)
        }
        if isSelecting {
            ToolbarItem(placement: .bottomBar) {
                LibrarySelectionBar(count: selectedIDs.count) { isConfirmingDelete = true }
            }
            .axisBehavior(.verticalPreferred)
        }
    }

    private func tap(_ item: LibraryItem) {
        if isSelecting {
            if selectedIDs.contains(item.id) { selectedIDs.remove(item.id) } else { selectedIDs.insert(item.id) }
        } else if item.kind == .clip {
            previewURL = item.pictureURL
        } else {
            path.append(item)
        }
    }

    private func setSelecting(_ isOn: Bool) {
        isSelecting = isOn
        selectedIDs = []
    }

    /// `-librarySelect on` opens in Select mode with the newest item selected, once the items have loaded.
    private func applyLaunchSelection() {
        guard !hasAppliedLaunch else { return }
        hasAppliedLaunch = true
        guard launch.startsInSelectMode, let first = library.items.first else { return }
        selectedIDs = [first.id]
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
