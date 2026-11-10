import OSLog
import QuickLookThumbnailing
import SwiftUI

/// The strip's Library item: a thumbnail of the newest photo or clip, or the Library symbol while the captures folder has
/// none. It opens the Library, which previews photos and clips, whenever the camera allows it.
struct LibraryThumbnail: View {
    private static let logger = Logger(subsystem: "local.opencam.app", category: "LibraryThumbnail")
    private static let side: CGFloat = 30

    let model: CameraModel

    @Environment(\.displayScale) private var displayScale
    @State private var thumbnail: UIImage?

    var body: some View {
        Button { model.openLibrary() } label: {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: Self.side, height: Self.side)
                    .clipShape(.rect(cornerRadius: Theme.Space.xs + 2))
            } else {
                Image(systemName: "photo.on.rectangle")
            }
        }
        .disabled(!model.canOpenLibrary)
        .accessibilityLabel("Library")
        .task(id: model.lastCapture) {
            model.loadLastCapture()
            thumbnail = await makeThumbnail(for: model.lastCapture)
        }
    }

    private func makeThumbnail(for url: URL?) async -> UIImage? {
        guard let url else { return nil }
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: Self.side * 2, height: Self.side * 2),
                                                   scale: displayScale, representationTypes: .thumbnail)
        do {
            return try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).uiImage
        } catch {
            Self.logger.error("[LibraryThumbnail:makeThumbnail] Thumbnail failed — {file: \(url.lastPathComponent, privacy: .public), reason: \(error.localizedDescription, privacy: .public)}")
            return nil
        }
    }
}
