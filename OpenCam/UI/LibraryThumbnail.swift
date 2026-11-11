import OSLog
import QuickLookThumbnailing
import SwiftUI

/// The strip's Library item: a stack of the newest photos and clips, or the Library symbol while the captures folder has
/// none. A photo is drawn by the Library's own thumbnail cache with its edit, so it looks as it does in the Library; a clip
/// (or anything without a Library) by Quick Look. A thumbnail already drawn is kept while its file and edit are unchanged,
/// so a new capture draws only its own. It opens the Library, which previews photos and clips, whenever the camera allows it.
struct LibraryThumbnail: View {
    private static let logger = Logger(subsystem: "local.opencam.app", category: "LibraryThumbnail")

    let model: CameraModel
    let library: LibraryStore?

    @Environment(\.displayScale) private var displayScale
    @State private var thumbnails: [CGImage] = []
    /// The drawn thumbnails by `key(for:)`, so an unchanged capture is not drawn again.
    @State private var drawn: [String: CGImage] = [:]

    /// With no thumbnail to draw the item shows the plain Library symbol.
    static func showsSymbol(for thumbnails: [CGImage]) -> Bool { thumbnails.isEmpty }

    var body: some View {
        Button { model.openLibrary() } label: {
            if Self.showsSymbol(for: thumbnails) {
                Image(systemName: "photo.on.rectangle")
            } else {
                ThumbnailStack(thumbnails: thumbnails)
            }
        }
        .disabled(!model.canOpenLibrary)
        .accessibilityLabel("Library")
        .task(id: request) {
            model.loadLastCapture()
            var images: [CGImage] = []
            var kept: [String: CGImage] = [:]
            for capture in captures() {
                let image: CGImage?
                if let cached = drawn[capture.key] {
                    image = cached
                } else {
                    image = await makeThumbnail(for: capture.url, item: capture.item)
                }
                guard let image else { continue }
                kept[capture.key] = image
                images.append(image)
            }
            guard !Task.isCancelled else { return }
            drawn = kept
            thumbnails = images
        }
    }

    /// The recent captures' keys, so an edit made in the Library draws again.
    private var request: [String] { captures().map(\.key) }

    /// Each recent capture with its Library item, found in one pass over the Library's items, and its key: the file name and,
    /// for a photo the Library knows, its thumbnail key, which carries its edit.
    private func captures() -> [(url: URL, item: LibraryItem?, key: String)] {
        let urls = model.recentCaptures
        let items = library?.captureItems(for: urls) ?? urls.map { _ in nil }
        return zip(urls, items).map { url, item in
            (url, item, "\(url.lastPathComponent)|\(item.flatMap { library?.thumbnailKey(for: $0) } ?? "")")
        }
    }

    private func makeThumbnail(for url: URL, item: LibraryItem?) async -> CGImage? {
        if let image = await library?.captureThumbnail(for: url, item: item) { return image }
        let side = ThumbnailStack.side * 2
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: side, height: side),
                                                   scale: displayScale, representationTypes: .thumbnail)
        do {
            return try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).cgImage
        } catch {
            Self.logger.error("[LibraryThumbnail:makeThumbnail] Thumbnail failed — {file: \(url.lastPathComponent, privacy: .public), reason: \(error.localizedDescription, privacy: .public)}")
            return nil
        }
    }
}
