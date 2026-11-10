import Foundation

/// One photo (with its RAW file when it has one) or one video clip in the Captures folder.
nonisolated struct LibraryItem: Sendable, Hashable, Identifiable {
    let kind: LibraryItemKind
    /// "OC_0001"; for a photo also the edit file's stem.
    let stem: String
    /// Photo: the editable picture (HEIC, HEIF, JPG, JPEG, PNG, else the DNG). Clip: the MOV.
    let pictureURL: URL
    /// Photo: the DNG when the stem has one. Clip: nil.
    let rawURL: URL?
    /// Clip: "<stem>.json" when present. Photo: nil.
    let sidecarURL: URL?
    /// The picture file's content modification date.
    let modified: Date

    var id: String { kind == .photo ? stem : stem + ".MOV" }
    var isEditable: Bool { kind == .photo }

    /// Every file that belongs to the item, without nils or duplicates.
    var fileURLs: [URL] {
        var urls = [pictureURL]
        for url in [rawURL, sidecarURL] {
            if let url, !urls.contains(url) { urls.append(url) }
        }
        return urls
    }
}
