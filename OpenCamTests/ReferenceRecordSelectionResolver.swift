import Foundation
@testable import OpenCam

/// The record resolver as it was before it was indexed (commit 5d1d3d3), kept as the oracle the indexed one must match.
nonisolated struct ReferenceRecordSelectionResolver: Sendable {
    private static let qualityOrder = [
        "4444 XQ", "4444", "422 HQ", "422", "422 LT", "422 Proxy",
        "ProRes RAW", "ProRes RAW HQ",
        "Max", "High", "Medium", "Low", "Standard",
    ]

    private let options: [VideoOption]

    /// Keeps the options for `lens?.id` only; no lens means no options.
    init(options: [VideoOption], lens: Lens?) {
        self.options = lens.map { lens in options.filter { $0.lensID == lens.id } } ?? []
    }

    func chips(_ row: RecordRow, for selection: RecordSelection) -> [Chip] {
        entries(row, for: selection).map(\.chip)
    }

    func reasonLine(_ row: RecordRow, for selection: RecordSelection) -> String? {
        chips(row, for: selection).first { !$0.isAvailable }?.reason
    }

    func select(_ row: RecordRow, chipID: String, in selection: RecordSelection) -> RecordSelection? {
        guard let entry = entries(row, for: selection).first(where: { $0.chip.id == chipID }),
              entry.chip.isAvailable else { return nil }
        return settled(applying(row, from: entry.option, to: selection))
    }

    func settled(_ selection: RecordSelection) -> RecordSelection? {
        guard !options.isEmpty else { return nil }
        var current = selection
        var pool = options
        for row in RecordRow.allCases {
            let same = pool.first { id(row, of: $0) == id(row, of: current) }
            guard let chosen = same ?? pick(row, from: pool, for: current) else { return nil }
            current = applying(row, from: chosen, to: current)
            pool = pool.filter { id(row, of: $0) == id(row, of: chosen) }
        }
        return current
    }

    func option(for selection: RecordSelection) -> VideoOption? {
        options.first { option in RecordRow.allCases.allSatisfy { id($0, of: option) == id($0, of: selection) } }
    }

    func defaultSelection() -> RecordSelection? {
        let preferred = RecordSelection(
            family: .hevc, quality: "High", resolution: .named(width: 3840, height: 2160),
            frameRate: 30, colour: .rec709
        )
        if option(for: preferred) != nil { return preferred }
        return options.first.flatMap { settled(selection(from: $0)) }
    }

    // MARK: Rows

    private typealias Entry = (chip: Chip, option: VideoOption)

    private func entries(_ row: RecordRow, for selection: RecordSelection) -> [Entry] {
        let above = RecordRow.allCases.prefix { $0 != row }
        let reachable = options.filter { option in above.allSatisfy { id($0, of: option) == id($0, of: selection) } }
        let listed = row == .quality ? options.filter { $0.codec.family == selection.family } : options
        var firstByID: [String: VideoOption] = [:]
        for option in listed where firstByID[id(row, of: option)] == nil {
            firstByID[id(row, of: option)] = option
        }
        return firstByID.values
            .sorted { (sortKey(row, of: $0), id(row, of: $0)) < (sortKey(row, of: $1), id(row, of: $1)) }
            .map { option in
                let isAvailable = reachable.contains { id(row, of: $0) == id(row, of: option) }
                let chip = Chip(
                    id: id(row, of: option),
                    title: title(row, of: option),
                    detail: row == .resolution ? option.resolution.detail : nil,
                    isAvailable: isAvailable,
                    reason: isAvailable ? nil : reason(row, for: option, in: selection)
                )
                return (chip, option)
            }
    }

    private func id(_ row: RecordRow, of option: VideoOption) -> String {
        switch row {
        case .codec: option.codec.family.rawValue
        case .quality: option.codec.quality
        case .resolution: option.resolution.id
        case .frameRate: String(option.frameRate)
        case .colour: option.colour.rawValue
        }
    }

    private func id(_ row: RecordRow, of selection: RecordSelection) -> String {
        switch row {
        case .codec: selection.family.rawValue
        case .quality: selection.quality
        case .resolution: selection.resolution.id
        case .frameRate: String(selection.frameRate)
        case .colour: selection.colour.rawValue
        }
    }

    private func title(_ row: RecordRow, of option: VideoOption) -> String {
        switch row {
        case .codec: option.codec.family.title
        case .quality: option.codec.quality
        case .resolution: option.resolution.label
        case .frameRate: String(option.frameRate)
        case .colour: option.colour.rawValue
        }
    }

    /// Ascending sort position within a row.
    private func sortKey(_ row: RecordRow, of option: VideoOption) -> Int {
        switch row {
        case .codec: CodecFamily.allCases.firstIndex(of: option.codec.family) ?? CodecFamily.allCases.count
        case .quality: Self.qualityOrder.firstIndex(of: option.codec.quality) ?? Self.qualityOrder.count
        case .resolution: -option.resolution.pixelCount
        case .frameRate: option.frameRate
        case .colour: ColourMode.allCases.firstIndex(of: option.colour) ?? ColourMode.allCases.count
        }
    }

    private func applying(_ row: RecordRow, from option: VideoOption, to selection: RecordSelection) -> RecordSelection {
        var result = selection
        switch row {
        case .codec: result.family = option.codec.family
        case .quality: result.quality = option.codec.quality
        case .resolution: result.resolution = option.resolution
        case .frameRate: result.frameRate = option.frameRate
        case .colour: result.colour = option.colour
        }
        return result
    }

    private func selection(from option: VideoOption) -> RecordSelection {
        RecordSelection(
            family: option.codec.family, quality: option.codec.quality,
            resolution: option.resolution, frameRate: option.frameRate, colour: option.colour
        )
    }

    /// Nearest valid value in `pool` for a row whose current value is not in it.
    private func pick(_ row: RecordRow, from pool: [VideoOption], for selection: RecordSelection) -> VideoOption? {
        let ordered = pool.sorted { sortKey(row, of: $0) < sortKey(row, of: $1) }
        switch row {
        case .frameRate:
            return ordered.last { $0.frameRate <= selection.frameRate } ?? ordered.first
        case .resolution:
            return ordered.first { $0.resolution.pixelCount <= selection.resolution.pixelCount } ?? ordered.first
        case .codec, .quality, .colour:
            return ordered.first
        }
    }

    // MARK: Reasons

    private func codecName(for selection: RecordSelection) -> String {
        options.first { $0.codec.family == selection.family && $0.codec.quality == selection.quality }?.codec.displayName
            ?? "\(selection.family.title) \(selection.quality)"
    }

    private func reason(_ row: RecordRow, for chip: VideoOption, in selection: RecordSelection) -> String? {
        let name = codecName(for: selection)
        switch row {
        case .codec, .quality:
            return nil
        case .resolution:
            let candidates = options.filter { $0.codec.family == selection.family && $0.codec.quality == selection.quality }
            if let largest = candidates.map(\.resolution).max(by: { $0.pixelCount < $1.pixelCount }),
               chip.resolution.pixelCount > largest.pixelCount {
                return "\(name) records at up to \(largest.label)."
            }
            return "\(name) is not available at \(chip.resolution.label)."
        case .frameRate:
            let label = selection.resolution.label
            let rates = options
                .filter {
                    $0.codec.family == selection.family && $0.codec.quality == selection.quality
                        && $0.resolution == selection.resolution
                }
                .map(\.frameRate)
            if let top = rates.max(), chip.frameRate > top { return "\(name) at \(label) records at up to \(top) fps." }
            if let bottom = rates.min(), chip.frameRate < bottom { return "\(name) at \(label) records at \(bottom) fps or more." }
            return "\(name) at \(label) does not record at \(chip.frameRate) fps."
        case .colour:
            let colour = chip.colour.rawValue
            let inFamily = options.filter { $0.codec.family == selection.family }
            if !inFamily.contains(where: { $0.colour == chip.colour }) {
                return "\(colour) is not available with \(selection.family.title)."
            }
            let atResolution = inFamily.filter { $0.codec.quality == selection.quality && $0.resolution == selection.resolution }
            if !atResolution.contains(where: { $0.colour == chip.colour }) {
                return "\(colour) is not available with \(name) at \(selection.resolution.label)."
            }
            return "\(colour) is not available at \(selection.frameRate) fps."
        }
    }
}
