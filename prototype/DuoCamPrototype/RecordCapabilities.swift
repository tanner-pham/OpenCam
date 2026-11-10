import Foundation

enum Codec: String, CaseIterable {
    case raw = "RAW", proRes = "ProRes", hevc = "HEVC", h264 = "H.264"
}

enum Resolution: String, CaseIterable {
    case openGate = "Open gate", uhd = "4K", qhd = "2.7K", fullHD = "1080p", hd = "720p"

    var size: String {
        switch self {
        case .openGate: "4032 x 3024"
        case .uhd: "3840 x 2160"
        case .qhd: "2704 x 1520"
        case .fullHD: "1920 x 1080"
        case .hd: "1280 x 720"
        }
    }

    /// Pixel count relative to 4K, used by the data rate estimate.
    var pixelRatio: Double {
        switch self {
        case .openGate: 1.47
        case .uhd: 1
        case .qhd: 0.5
        case .fullHD: 0.25
        case .hd: 0.11
        }
    }
}

enum ColourSpace: String, CaseIterable {
    case rec709 = "Rec. 709", hlg = "HLG", dolbyVision = "Dolby Vision"
    case appleLog = "Apple Log", appleLog2 = "Apple Log 2", sensorRAW = "Sensor RAW"

    var shortName: String {
        switch self {
        case .appleLog: "Log"
        case .appleLog2: "Log 2"
        case .sensorRAW: ""
        default: rawValue
        }
    }

    var isLog: Bool { self == .appleLog || self == .appleLog2 }
}

enum RecordRow: CaseIterable {
    case codec, quality, resolution, frameRate, colour

    /// Grid columns per row, so wrapped rows line up. Wide is the horizontal layout.
    func columns(isWide: Bool) -> Int {
        switch self {
        case .codec: 4
        case .quality: isWide ? 5 : 3
        case .resolution: isWide ? 5 : 3
        case .frameRate: isWide ? 8 : 4
        case .colour: isWide ? 5 : 3
        }
    }

    var title: String {
        switch self {
        case .codec: "Codec"
        case .quality: "Quality"
        case .resolution: "Resolution"
        case .frameRate: "Frame rate"
        case .colour: "Colour"
        }
    }
}

struct RecordSettings: Equatable {
    var codec: Codec
    var quality: String
    var resolution: Resolution
    var frameRate: Int
    var colour: ColourSpace

    static let initial = RecordSettings(codec: .proRes, quality: "422 HQ", resolution: .uhd, frameRate: 30, colour: .appleLog2)

    var summaryParts: [String] {
        [codec.rawValue, resolution.rawValue, colour.shortName].filter { !$0.isEmpty }
    }
}

struct Chip: Identifiable {
    let id: String
    var detail: String?
    var isAvailable = true
    var reason: String?
}

/// Fixture standing in for what the device will report. Every picker renders from this.
struct RecordCapabilities {
    let qualities: [Codec: [String]]
    let frameRates: [Int]
    let freeGB: Double
    /// GB per minute at 4K and 30 fps, by quality.
    let gbPerMinute4K30: [String: Double]

    static let fixture = RecordCapabilities(
        qualities: [
            .raw: ["CinemaDNG"],
            .proRes: ["4444", "422 HQ", "422", "422 LT", "422 Proxy"],
            .hevc: ["10-bit High", "10-bit Standard", "8-bit"],
            .h264: ["High", "Standard"],
        ],
        frameRates: [24, 25, 30, 48, 50, 60, 100, 120],
        freeGB: 128,
        gbPerMinute4K30: [
            "CinemaDNG": 13.6, "4444": 9.2, "422 HQ": 6.1, "422": 4.1, "422 LT": 2.8, "422 Proxy": 1.3,
            "10-bit High": 0.9, "10-bit Standard": 0.5, "8-bit": 0.4, "High": 0.8, "Standard": 0.4,
        ]
    )

    // MARK: Chips

    func chips(_ row: RecordRow, for s: RecordSettings) -> [Chip] {
        switch row {
        case .codec:
            return Codec.allCases.map { Chip(id: $0.rawValue) }
        case .quality:
            return (qualities[s.codec] ?? []).map { Chip(id: $0) }
        case .resolution:
            let isOpenGateOK = s.codec == .raw || s.codec == .proRes
            return Resolution.allCases.map { res in
                let isBlocked = res == .openGate && !isOpenGateOK
                return Chip(id: res.rawValue, detail: res.size, isAvailable: !isBlocked,
                            reason: isBlocked ? "Open gate needs RAW or ProRes." : nil)
            }
        case .frameRate:
            let limit = frameRateLimit(s.codec)
            return frameRates.map { rate in
                let isBlocked = rate > limit
                return Chip(id: String(rate), isAvailable: !isBlocked,
                            reason: isBlocked ? "\(s.codec.rawValue) records at up to \(limit) fps." : nil)
            }
        case .colour:
            if s.codec == .raw { return [Chip(id: ColourSpace.sensorRAW.rawValue)] }
            return ColourSpace.allCases.filter { $0 != .sensorRAW }.map { colourChip($0, s) }
        }
    }

    private func frameRateLimit(_ codec: Codec) -> Int {
        switch codec {
        case .raw, .proRes: 30
        case .h264: 60
        case .hevc: 120
        }
    }

    private func colourChip(_ colour: ColourSpace, _ s: RecordSettings) -> Chip {
        func blocked(_ reason: String) -> Chip { Chip(id: colour.rawValue, isAvailable: false, reason: reason) }
        let available = Chip(id: colour.rawValue)
        if colour == .rec709 { return available }
        if s.codec == .h264 { return blocked("H.264 records Rec. 709 only.") }
        if colour == .dolbyVision && s.codec != .hevc { return blocked("Dolby Vision needs HEVC.") }
        if colour.isLog && s.frameRate > 30 { return blocked("\(colour.rawValue) records at up to 30 fps.") }
        if s.codec == .hevc && s.quality == "8-bit" { return blocked("\(colour.rawValue) needs 10-bit.") }
        return available
    }

    // MARK: Moving invalid rows

    /// Applies an edit, then moves each lower row that the edit ruled out to its nearest valid chip.
    func settled(_ new: RecordSettings, from old: RecordSettings) -> RecordSettings {
        var s = new
        let list = qualities[s.codec] ?? []
        if !list.contains(s.quality) {
            let oldIndex = qualities[old.codec]?.firstIndex(of: old.quality) ?? 0
            s.quality = list[safe: min(oldIndex, list.count - 1)] ?? s.quality
        }
        if let id = nearestAvailable(chips(.resolution, for: s), to: s.resolution.rawValue), let r = Resolution(rawValue: id) {
            s.resolution = r
        }
        if let id = nearestAvailable(chips(.frameRate, for: s), to: String(s.frameRate)), let f = Int(id) {
            s.frameRate = f
        }
        if let id = nearestAvailable(chips(.colour, for: s), to: s.colour.rawValue), let c = ColourSpace(rawValue: id) {
            s.colour = c
        }
        return s
    }

    private func nearestAvailable(_ chips: [Chip], to id: String) -> String? {
        let index = chips.firstIndex { $0.id == id } ?? 0
        return chips.enumerated()
            .filter { $0.element.isAvailable }
            .min { abs($0.offset - index) < abs($1.offset - index) }?.element.id
    }

    // MARK: Estimates

    func gbPerMinute(for s: RecordSettings) -> Double {
        (gbPerMinute4K30[s.quality] ?? 0) * s.resolution.pixelRatio * Double(s.frameRate) / 30
    }

    func minutesLeft(for s: RecordSettings) -> Int {
        let rate = gbPerMinute(for: s)
        return rate > 0 ? Int((freeGB / rate).rounded()) : 0
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
