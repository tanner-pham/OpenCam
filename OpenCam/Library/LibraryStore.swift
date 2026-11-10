import CoreGraphics
import Foundation
import Observation
import OSLog

/// The library's items, their edits and the looks, for the screens to show.
@MainActor @Observable final class LibraryStore {
    private static let logger = Logger(subsystem: "local.opencam.app", category: "LibraryStore")

    let captures: CaptureStore
    let edits: EditStore
    let lookStore: LookStore
    private let thumbnails: ThumbnailCache

    /// Photos and clips, newest first.
    private(set) var items: [LibraryItem] = []
    private(set) var looks: [Look] = []
    private var editsByStem: [String: PhotoEdit] = [:]
    /// Photos whose edit file exists but could not be loaded, by stem, with why: unreadable, or from a newer build in a shape
    /// this one cannot decode. Such a photo shows unedited, and no batch change or delete touches its edit.
    private var editFailures: [String: EditStoreError] = [:]

    init(captures: CaptureStore, edits: EditStore, looks: LookStore, thumbnails: ThumbnailCache) {
        self.captures = captures
        self.edits = edits
        self.lookStore = looks
        self.thumbnails = thumbnails
    }

    /// Reads the items, the photos' edits and the looks. An edit that cannot be loaded is logged and kept apart in
    /// `editFailures`; the photo shows unedited.
    func reload() {
        let scanned = LibraryScanner.items(in: captures.directory)
        var loaded: [String: PhotoEdit] = [:]
        var failures: [String: EditStoreError] = [:]
        for item in scanned where item.isEditable {
            do {
                loaded[item.stem] = try edits.load(stem: item.stem)
            } catch {
                Self.logger.error("\(error.description, privacy: .public)")
                failures[item.stem] = error
            }
        }
        items = scanned
        editsByStem = loaded
        editFailures = failures
        looks = lookStore.all()
    }

    /// Loads and imports the pictures into the shared Captures folder one at a time, then reloads once so they show.
    func importPhotos<Source>(_ sources: [Source], load: (Source) async -> ImportCandidate?) async -> ImportResult {
        let result = await PhotoImporter.importEach(sources, into: captures, load: load)
        reload()
        return result
    }

    func edit(for item: LibraryItem) -> PhotoEdit {
        item.isEditable ? editsByStem[item.stem] ?? PhotoEdit() : PhotoEdit()
    }

    func thumbnailKey(for item: LibraryItem) -> String {
        ThumbnailCache.key(fileName: item.pictureURL.lastPathComponent, modified: item.modified, edit: edit(for: item))
    }

    /// `.failed` when the file cannot be decoded.
    func thumbnail(for item: LibraryItem) async -> ThumbnailState {
        do {
            return .ready(try await thumbnails.thumbnail(for: item, edit: edit(for: item)))
        } catch {
            Self.logger.error("\(error.description, privacy: .public)")
            return .failed
        }
    }

    /// Each photo's edit becomes a copy of the look, so later changes to the look never reach it. Clips are skipped.
    func applyLook(_ look: Look, to items: [LibraryItem]) throws(LibraryError) -> LookChange {
        let edit = PhotoEdit(adjustments: look.adjustments, lookName: look.name)
        return try changeEdits(of: items, action: .applied) { item throws(EditStoreError) in
            try edits.save(edit, stem: item.stem)
            return true
        }
    }

    /// Removes the whole edit of each photo that has a look; photos without one and clips are left as they are.
    func removeLook(from items: [LibraryItem]) throws(LibraryError) -> LookChange {
        try changeEdits(of: items, action: .removed) { item throws(EditStoreError) in
            guard edit(for: item).lookName != nil else { return false }
            try edits.remove(stem: item.stem)
            return true
        }
    }

    /// Each item's edit for the confirmation counts in `LookChange`: nil for a clip.
    func lookEdits(for items: [LibraryItem]) -> [PhotoEdit?] {
        items.map { $0.isEditable ? edit(for: $0) : nil }
    }

    /// Runs `change` on each photo (true when it changed the photo). A photo whose edit is from a newer version is left as it
    /// is and counted; one whose edit could not be loaded is left as it is and counted as failed; any other failure is
    /// logged, counted, and the rest still run. Then the store reloads; when any photo
    /// failed, `.lookChangeIncomplete` carries what happened to every item.
    private func changeEdits(of items: [LibraryItem], action: LookChange.Action,
                             _ change: (LibraryItem) throws(EditStoreError) -> Bool) throws(LibraryError) -> LookChange {
        var changed = 0, clips = 0, newer = 0, failed = 0
        var firstReason: String?
        for item in items {
            guard item.isEditable else {
                clips += 1
                continue
            }
            do throws(EditStoreError) {
                // An edit that could not be loaded is never passed to `change`: what it holds is unknown.
                if let failure = editFailures[item.stem] { throw failure }
                if try change(item) { changed += 1 }
            } catch {
                Self.logger.error("\(error.description, privacy: .public)")
                switch error {
                case .newerVersion:
                    newer += 1
                case .unreadable, .unwritable:
                    failed += 1
                    firstReason = firstReason ?? error.description
                }
            }
        }
        reload()
        let result = LookChange(action: action, photosChanged: changed, clipsSkipped: clips, newerSkipped: newer, photosFailed: failed)
        if let firstReason {
            let error = LibraryError.lookChangeIncomplete(change: result, reason: firstReason)
            Self.logger.error("\(error.description, privacy: .public)")
            throw error
        }
        return result
    }

    /// Each item goes whole or stays: a photo's edit file is removed first, then its files. A photo whose edit is from a newer
    /// version, or one that cannot be read, stays whole, because this build never removes such a file and an orphan edit file
    /// would still raise the next number. The other items are still deleted; then the store reloads and the first error is
    /// thrown, `.newerEdit` first, then `.unreadableEdit`, then any other kind.
    func delete(_ items: [LibraryItem]) throws(LibraryError) {
        var problems: [LibraryError] = []
        for item in items {
            if item.isEditable {
                do {
                    try edits.remove(stem: item.stem)
                } catch {
                    switch error {
                    case .newerVersion(let path, let version): problems.append(.newerEdit(path: path, version: version))
                    case .unreadable(let path, let reason): problems.append(.unreadableEdit(path: path, reason: reason))
                    case .unwritable: problems.append(.editFailed(stem: item.stem, reason: error.description))
                    }
                    continue
                }
            }
            for url in item.fileURLs {
                do {
                    try FileManager.default.removeItem(at: url)
                } catch {
                    problems.append(.deleteFailed(path: url.path(percentEncoded: false), reason: error.localizedDescription))
                    break
                }
            }
        }
        reload()
        for problem in problems { Self.logger.error("\(problem.description, privacy: .public)") }
        let newer = problems.first { if case .newerEdit = $0 { true } else { false } }
        let unreadable = problems.first { if case .unreadableEdit = $0 { true } else { false } }
        if let error = newer ?? unreadable ?? problems.first { throw error }
    }
}
