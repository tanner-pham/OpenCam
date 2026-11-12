import Foundation

/// One lens's video options, indexed once when it is made: each option's id in every row is numbered up front and the
/// options are keyed by their five values, so a lookup is a dictionary read and a row of chips is one integer pass over the
/// lens.
/// The model keeps one per lens and rebuilds them only when the capabilities change.
nonisolated struct RecordSelectionResolver: Sendable {
    private static let qualityOrder = [
        "4444 XQ", "4444", "422 HQ", "422", "422 LT", "422 Proxy",
        "ProRes RAW", "ProRes RAW HQ",
        "Max", "High", "Medium", "Low", "Standard",
    ]

    private static let columnCount = RecordRow.allCases.count

    private let options: [VideoOption]
    /// `codes[i * columnCount + c]` numbers `options[i]`'s id in column `c` (`RecordRow.allCases[c]`), so a row is compared
    /// by integers instead of strings.
    private let codes: [Int]
    /// Per column, the number given to each id.
    private let codeByID: [[String: Int]]
    /// The first option, in the device's order, for each set of values.
    private let firstByKey: [RecordOptionKey: VideoOption]

    /// The keys only the writer records: those no scanned option has.
    private let writerKeys: Set<RecordOptionKey>

    /// Keeps the options for `lens?.id` only; no lens means no options.
    init(options: [VideoOption], writerOptions: [VideoOption] = [], lens: Lens?) {
        self.init(lensOptions: lens.map { lens in options.filter { $0.lensID == lens.id } } ?? [],
                  writerOptions: lens.map { lens in writerOptions.filter { $0.lensID == lens.id } } ?? [])
    }

    /// `scanned` is already one lens's, in the device's order; its writer options follow, so a tie on the five values
    /// settles on a scanned option.
    init(lensOptions scanned: [VideoOption], writerOptions: [VideoOption] = []) {
        let lensOptions = scanned + writerOptions
        var writer: Set<RecordOptionKey> = []
        var tables = Array(repeating: [String: Int](), count: Self.columnCount)
        var codes: [Int] = []
        codes.reserveCapacity(lensOptions.count * Self.columnCount)
        var first: [RecordOptionKey: VideoOption] = [:]
        for (index, option) in lensOptions.enumerated() {
            for (column, row) in RecordRow.allCases.enumerated() {
                let id = Self.id(row, of: option)
                if let code = tables[column][id] {
                    codes.append(code)
                } else {
                    let code = tables[column].count
                    tables[column][id] = code
                    codes.append(code)
                }
            }
            let key = RecordOptionKey(option)
            if first[key] == nil {
                first[key] = option
                if index >= scanned.count { writer.insert(key) }
            }
        }
        writerKeys = writer
        options = lensOptions
        self.codes = codes
        codeByID = tables
        firstByKey = first
    }

    /// With `freeBytes`, the available Codec and Quality chips also carry the estimate for the selection a tap would settle on.
    func chips(_ row: RecordRow, for selection: RecordSelection, freeBytes: Int64? = nil) -> [Chip] {
        let rowEntries = entries(row, for: selection)
        guard let freeBytes, row == .codec || row == .quality else { return rowEntries.map(\.chip) }
        return rowEntries.map { entry in
            guard entry.chip.isAvailable else { return entry.chip }
            let tapped = applying(row, from: entry.option, to: selection)
            // A tap that lands on a real option settles on itself, so only the others walk the lens.
            guard let option = option(for: tapped) ?? settled(tapped).flatMap({ option(for: $0) }) else { return entry.chip }
            var chip = entry.chip
            chip.estimate = DataRateEstimator.estimate(for: option, freeBytes: freeBytes)
            return chip
        }
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
        var pool = Array(options.indices)
        for (column, row) in RecordRow.allCases.enumerated() {
            let wanted = code(column, of: current)
            let same = pool.first { codes[$0 * Self.columnCount + column] == wanted }
            guard let chosen = same ?? pick(row, from: pool, for: current) else { return nil }
            current = applying(row, from: options[chosen], to: current)
            let chosenCode = codes[chosen * Self.columnCount + column]
            pool.removeAll { codes[$0 * Self.columnCount + column] != chosenCode }
        }
        return current
    }

    func option(for selection: RecordSelection) -> VideoOption? {
        firstByKey[RecordOptionKey(selection)]
    }

    /// Which recorder records `selection`: the writer only for an option no scanned option shares.
    func recorder(for selection: RecordSelection) -> RecorderPath {
        writerKeys.contains(RecordOptionKey(selection)) ? .writer : .system
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

    /// The number of `selection`'s id in `column`, or -1 when no option of the lens has it.
    private func code(_ column: Int, of selection: RecordSelection) -> Int {
        codeByID[column][Self.id(RecordRow.allCases[column], of: selection)] ?? -1
    }

    /// One pass over the lens: the ids reachable from the rows above, and the first option of every id the row lists.
    /// Reasons are worked out once per call, and only when a chip is dimmed.
    private func entries(_ row: RecordRow, for selection: RecordSelection) -> [Entry] {
        let column = Self.column(of: row)
        let selectionCodes = (0..<Self.columnCount).map { code($0, of: selection) }
        let idCount = codeByID[column].count
        var isReachable = [Bool](repeating: false, count: idCount)
        var firstIndex = [Int](repeating: -1, count: idCount)
        for index in options.indices {
            let base = index * Self.columnCount
            var matchesAbove = true
            for above in 0..<column where codes[base + above] != selectionCodes[above] {
                matchesAbove = false
                break
            }
            let rowCode = codes[base + column]
            if matchesAbove { isReachable[rowCode] = true }
            // The quality row lists the selected codec family's qualities only.
            if firstIndex[rowCode] < 0, row != .quality || codes[base] == selectionCodes[0] {
                firstIndex[rowCode] = index
            }
        }
        let listed = firstIndex.indices.filter { firstIndex[$0] >= 0 }.map { (option: options[firstIndex[$0]], isAvailable: isReachable[$0]) }
        var reasonFor: ((VideoOption) -> String?)?
        return listed
            .sorted { (sortKey(row, of: $0.option), Self.id(row, of: $0.option)) < (sortKey(row, of: $1.option), Self.id(row, of: $1.option)) }
            .map { option, isAvailable in
                let chipID = Self.id(row, of: option)
                var reason: String?
                if !isAvailable {
                    let make = reasonFor ?? reasons(row, in: selection)
                    reasonFor = make
                    reason = make(option)
                }
                let chip = Chip(
                    id: chipID,
                    title: title(row, of: option),
                    detail: row == .resolution ? option.resolution.detail : nil,
                    isAvailable: isAvailable,
                    reason: reason
                )
                return (chip, option)
            }
    }

    private static func column(of row: RecordRow) -> Int {
        switch row {
        case .codec: 0
        case .quality: 1
        case .resolution: 2
        case .frameRate: 3
        case .colour: 4
        }
    }

    private static func id(_ row: RecordRow, of option: VideoOption) -> String {
        switch row {
        case .codec: option.codec.family.rawValue
        case .quality: option.codec.quality
        case .resolution: option.resolution.id
        case .frameRate: String(option.frameRate)
        case .colour: option.colour.rawValue
        }
    }

    private static func id(_ row: RecordRow, of selection: RecordSelection) -> String {
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

    /// Nearest valid value in `pool` (indices into `options`) for a row whose current value is not in it.
    private func pick(_ row: RecordRow, from pool: [Int], for selection: RecordSelection) -> Int? {
        let ordered = pool.sorted { sortKey(row, of: options[$0]) < sortKey(row, of: options[$1]) }
        switch row {
        case .frameRate:
            return ordered.last { options[$0].frameRate <= selection.frameRate } ?? ordered.first
        case .resolution:
            return ordered.first { options[$0].resolution.pixelCount <= selection.resolution.pixelCount } ?? ordered.first
        case .codec, .quality, .colour:
            return ordered.first
        }
    }

    // MARK: Reasons

    private func codecName(for selection: RecordSelection) -> String {
        options.first { $0.codec.family == selection.family && $0.codec.quality == selection.quality }?.codec.displayName
            ?? "\(selection.family.title) \(selection.quality)"
    }

    /// The reason for each dimmed chip of `row`; what it needs from the lens's options is read once, here.
    private func reasons(_ row: RecordRow, in selection: RecordSelection) -> (VideoOption) -> String? {
        switch row {
        case .codec, .quality:
            return { _ in nil }
        case .resolution:
            let name = codecName(for: selection)
            let largest = options
                .filter { $0.codec.family == selection.family && $0.codec.quality == selection.quality }
                .map(\.resolution)
                .max(by: { $0.pixelCount < $1.pixelCount })
            return { chip in
                if let largest, chip.resolution.pixelCount > largest.pixelCount {
                    return "\(name) records at up to \(largest.label)."
                }
                return "\(name) is not available at \(chip.resolution.label)."
            }
        case .frameRate:
            let name = codecName(for: selection)
            let label = selection.resolution.label
            let rates = options
                .filter {
                    $0.codec.family == selection.family && $0.codec.quality == selection.quality
                        && $0.resolution == selection.resolution
                }
                .map(\.frameRate)
            let top = rates.max(), bottom = rates.min()
            return { chip in
                if let top, chip.frameRate > top { return "\(name) at \(label) records at up to \(top) fps." }
                if let bottom, chip.frameRate < bottom { return "\(name) at \(label) records at \(bottom) fps or more." }
                return "\(name) at \(label) does not record at \(chip.frameRate) fps."
            }
        case .colour:
            let name = codecName(for: selection)
            let inFamily = options.filter { $0.codec.family == selection.family }
            let familyColours = Set(inFamily.map(\.colour))
            let resolutionColours = Set(inFamily
                .filter { $0.codec.quality == selection.quality && $0.resolution == selection.resolution }
                .map(\.colour))
            return { chip in
                let colour = chip.colour.rawValue
                if !familyColours.contains(chip.colour) {
                    return "\(colour) is not available with \(selection.family.title)."
                }
                if !resolutionColours.contains(chip.colour) {
                    return "\(colour) is not available with \(name) at \(selection.resolution.label)."
                }
                return "\(colour) is not available at \(selection.frameRate) fps."
            }
        }
    }
}
