import Foundation

/// What a photo's files are: "RAW", "HEIF", "RAW + HEIF", "JPEG", "RAW + JPEG" or "PNG".
nonisolated struct FormatDesignation: Sendable, Equatable {
    /// Nil when the item is a DNG alone.
    let picture: PictureKind?
    let hasRAW: Bool

    var title: String {
        switch (picture, hasRAW) {
        case (nil, _): "RAW"
        case (let picture?, true): "RAW + \(picture.rawValue)"
        case (let picture?, false): picture.rawValue
        }
    }

    /// Nil for a clip.
    static func of(_ item: LibraryItem) -> FormatDesignation? {
        guard item.kind == .photo else { return nil }
        return FormatDesignation(picture: PictureKind(fileExtension: item.pictureURL.pathExtension), hasRAW: item.rawURL != nil)
    }
}
