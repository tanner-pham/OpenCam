import Foundation

/// Finds the library items among the files of the Captures folder.
nonisolated enum LibraryScanner {
    /// Compared uppercased.
    static let pictureExtensions: Set<String> = ["DNG", "HEIC", "HEIF", "JPG", "JPEG", "PNG"]
    static let clipExtensions: Set<String> = ["MOV"]

    /// Picture extensions from most to least preferred as the editable picture.
    private static let pictureOrder = ["HEIC", "HEIF", "JPG", "JPEG", "PNG", "DNG"]

    /// Reads the folder's names and the pictures' modification dates, then groups them. An unreadable folder has no items.
    static func items(in directory: URL) -> [LibraryItem] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))) ?? []
        return group(names: names, directory: directory) { name in
            let url = directory.appending(path: name, directoryHint: .notDirectory)
            return (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
        }
    }

    /// Photo files group by stem (the name up to the first dot) into one photo item; each MOV is one clip carrying `<stem>.json`
    /// as its sidecar. Edit files, reports, sidecars without a clip and other files are not items.
    /// Items with an `OC_` number come first, highest first (a photo before a clip of the same number), then the rest by name.
    static func group(names: [String], directory: URL, modified: (String) -> Date = { _ in .distantPast }) -> [LibraryItem] {
        let nameSet = Set(names)
        var picturesByStem: [String: [String: String]] = [:]   // stem -> uppercased extension -> file name
        var items: [LibraryItem] = []

        for name in names {
            guard let dot = name.firstIndex(of: "."), dot != name.startIndex, let lastDot = name.lastIndex(of: ".") else { continue }
            let stem = String(name[..<dot])
            let fileExtension = name[name.index(after: lastDot)...].uppercased()
            if pictureExtensions.contains(fileExtension), dot == lastDot {
                picturesByStem[stem, default: [:]][fileExtension] = name
            } else if clipExtensions.contains(fileExtension), dot == lastDot {
                let url = directory.appending(path: name, directoryHint: .notDirectory)
                let key = CaptureStore.clipKey(for: url)
                let sidecarName = String(key[..<key.index(key.endIndex, offsetBy: -fileExtension.count)]) + "json"
                let sidecarURL = nameSet.contains(sidecarName) ? directory.appending(path: sidecarName, directoryHint: .notDirectory) : nil
                items.append(LibraryItem(kind: .clip, stem: stem, pictureURL: url, rawURL: nil, sidecarURL: sidecarURL, modified: modified(name)))
            }
        }

        for (stem, files) in picturesByStem {
            guard let best = pictureOrder.first(where: { files[$0] != nil }), let bestName = files[best] else { continue }
            let rawURL = files["DNG"].map { directory.appending(path: $0, directoryHint: .notDirectory) }
            items.append(LibraryItem(kind: .photo, stem: stem, pictureURL: directory.appending(path: bestName, directoryHint: .notDirectory),
                                     rawURL: rawURL, sidecarURL: nil, modified: modified(bestName)))
        }

        return items.sorted { a, b in
            switch (sequence(ofStem: a.stem), sequence(ofStem: b.stem)) {
            case let (x?, y?):
                if x != y { return x > y }
                return a.kind == .photo && b.kind == .clip
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil):
                if a.stem != b.stem { return a.stem < b.stem }
                return a.kind == .photo && b.kind == .clip
            }
        }
    }

    /// "OC_0012" is 12; a stem without the prefix, or without digits after it, has no number.
    static func sequence(ofStem stem: String) -> Int? {
        guard stem.hasPrefix("OC_") else { return nil }
        let digits = stem.dropFirst(3)
        guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int(digits)
    }
}
