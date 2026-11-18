import AVKit
import SwiftUI

/// The Library's navigation destination for a clip: the system player over a line of its recording details, with Share and
/// Delete in the toolbar. A clip plays as recorded, whatever its colour mode.
struct ClipScreen: View {
    let item: LibraryItem
    let library: LibraryStore
    let onDone: () -> Void

    @State private var player: AVPlayer?
    @State private var info = ClipInfo(sidecar: nil)
    @State private var isConfirmingDelete = false
    @State private var isShowingDeleteFailure = false

    init(item: LibraryItem, library: LibraryStore, onDone: @escaping () -> Void) {
        self.item = item
        self.library = library
        self.onDone = onDone
    }

    var body: some View {
        VStack(spacing: 0) {
            if let player {
                VideoPlayer(player: player)
            } else {
                Color.black.overlay { ProgressView() }
            }
            InfoLine(title: LibraryCopy.clipInfoTitle, summary: info.summary, rows: info.rows)
        }
        .navigationTitle(item.stem)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ShareLink(item: item.pictureURL) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .labelStyle(.iconOnly)
                Button("Delete", systemImage: "trash", role: .destructive) { isConfirmingDelete = true }
                    .labelStyle(.iconOnly)
                    .tint(.red)
            }
        }
        .task(id: item.id) {
            let player = AVPlayer(url: item.pictureURL)
            self.player = player
            player.play()
        }
        .task(id: item.id) { info = await ClipInfo.load(for: item) }
        .onDisappear { player?.pause() }
        .confirmationDialog(LibraryCopy.deleteClipTitle, isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: delete)
        } message: {
            Text(LibraryCopy.deleteClipMessage)
        }
        .alert(LibraryCopy.deleteFailed, isPresented: $isShowingDeleteFailure) {
            Button("OK") {}
        }
    }

    private func delete() {
        player?.pause()
        do throws(LibraryError) {
            try library.delete([item])
            onDone()
        } catch {
            // The store has logged the cause; the person sees a fixed sentence.
            isShowingDeleteFailure = true
        }
    }
}
