import Foundation

nonisolated struct PhotoSelectionResolver: Sendable {
    private let allOptions: [PhotoOption]
    private let lenses: [Lens]
    private let lensID: String

    init(options: [PhotoOption], lenses: [Lens], lensID: String) {
        self.allOptions = options
        self.lenses = lenses
        self.lensID = lensID
    }

    private var options: [PhotoOption] { allOptions.filter { $0.lensID == lensID } }

    func chips(_ row: PhotoRow, for selection: PhotoSelection) -> [Chip] {
        switch row {
        case .format: formatChips()
        case .resolution: resolutionChips(for: selection)
        }
    }

    /// The reason of the first dimmed chip in the row.
    func reasonLine(_ row: PhotoRow, for selection: PhotoSelection) -> String? {
        chips(row, for: selection).first { !$0.isAvailable }?.reason
    }

    func select(_ row: PhotoRow, chipID: String, in selection: PhotoSelection) -> PhotoSelection? {
        guard let chip = chips(row, for: selection).first(where: { $0.id == chipID }), chip.isAvailable else { return nil }
        var changed = selection
        switch row {
        case .format:
            guard let format = PhotoFormat(rawValue: chipID) else { return nil }
            changed.format = format
        case .resolution:
            guard let megapixels = Int(chipID) else { return nil }
            changed.megapixels = megapixels
        }
        return settled(changed)
    }

    func settled(_ selection: PhotoSelection) -> PhotoSelection? {
        let lensOptions = options
        let formats = PhotoFormat.allCases.filter { format in lensOptions.contains { $0.format == format } }
        guard let format = formats.contains(selection.format) ? selection.format : formats.first else { return nil }
        let sizes = Set(lensOptions.filter { $0.format == format }.map(\.megapixels)).sorted(by: >)
        let megapixels = sizes.contains(selection.megapixels)
            ? selection.megapixels
            : (sizes.first { $0 <= selection.megapixels } ?? sizes.first)
        return megapixels.map { PhotoSelection(format: format, megapixels: $0) }
    }

    func option(for selection: PhotoSelection) -> PhotoOption? {
        options.first { $0.format == selection.format && $0.megapixels == selection.megapixels }
    }

    func defaultSelection() -> PhotoSelection? {
        let lensOptions = options
        for format in [PhotoFormat.rawPlusHEIF, .heif] {
            if let largest = lensOptions.filter({ $0.format == format }).map(\.megapixels).max() {
                return PhotoSelection(format: format, megapixels: largest)
            }
        }
        return nil
    }

    // MARK: Chips

    private func formatChips() -> [Chip] {
        PhotoFormat.allCases.compactMap { format in
            guard allOptions.contains(where: { $0.format == format }) else { return nil }
            let isAvailable = options.contains { $0.format == format }
            return Chip(
                id: format.rawValue, title: format.rawValue, detail: nil,
                isAvailable: isAvailable, reason: isAvailable ? nil : formatReason(format)
            )
        }
    }

    private func resolutionChips(for selection: PhotoSelection) -> [Chip] {
        let sizes = Set(options.map(\.megapixels)).sorted(by: >)
        let offered = options.filter { $0.format == selection.format }.map(\.megapixels)
        return sizes.map { size in
            let isAvailable = offered.contains(size)
            var reason: String?
            if !isAvailable {
                if let top = offered.max(), size > top {
                    reason = "\(selection.format.rawValue) records at up to \(top) MP."
                } else {
                    reason = "\(selection.format.rawValue) is not available at \(size) MP."
                }
            }
            return Chip(id: String(size), title: "\(size) MP", detail: nil, isAvailable: isAvailable, reason: reason)
        }
    }

    private func formatReason(_ format: PhotoFormat) -> String {
        let ids = Set(allOptions.filter { $0.format == format }.map(\.lensID))
        let names = lenses.filter { ids.contains($0.id) }.map(\.label)
        guard let last = names.last else { return "\(format.rawValue) is not available on this lens." }
        let list = names.count == 1 ? last : names.dropLast().joined(separator: ", ") + " or " + last
        return "\(format.includesRAW ? "RAW" : format.rawValue) needs the \(list) lens."
    }
}
