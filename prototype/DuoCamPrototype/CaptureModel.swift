import SwiftUI

enum Readout: String, CaseIterable, Identifiable {
    case fps, shutter, timecode, iso, wb, tint, ev

    var id: String { rawValue }

    var caption: String {
        switch self {
        case .fps: "FPS"
        case .shutter: "SHUTTER"
        case .timecode: "TIMECODE"
        case .iso: "ISO"
        case .wb: "WB"
        case .tint: "TINT"
        case .ev: "EV"
        }
    }

    var isAdjustable: Bool { self != .timecode }
}

enum Lens: String, CaseIterable, Identifiable {
    case ultraWide = "0.5x", main = "1x", tele = "2x", outerFront = "Outer front", innerFront = "Inner front"
    var id: String { rawValue }

    /// Short label for the strip.
    var shortName: String {
        switch self {
        case .outerFront: "Outer"
        case .innerFront: "Inner"
        default: rawValue
        }
    }
}

enum LUTChoice: String, CaseIterable, Identifiable {
    case off = "Off", log2 = "Log 2 to Rec. 709", imported = "Imported"
    var id: String { rawValue }
}

enum Sheet: String, Identifiable {
    case record, monitor, audio
    var id: String { rawValue }
}

struct MonitorSettings {
    var isZebraOn = true
    var zebraThreshold = 95.0
    var isPeakingOn = true
    var isFalseColourOn = false
    var isHistogramOn = true
    var isWaveformOn = false
    var frameGuide = "Off"
    var isGridOn = true
    var isLevelOn = false

    static let frameGuides = ["Off", "1.85:1", "2.39:1", "1:1", "9:16"]
}

struct AudioInput: Identifiable, Equatable {
    let name: String
    let isConnected: Bool
    var id: String { name }
}

struct AudioSettings {
    var input = "iPhone microphone"
    var gain = 6.0
    var format = "Linear PCM"
    let hasHeadphones = false
    let inputs = [
        AudioInput(name: "iPhone microphone", isConnected: true),
        AudioInput(name: "USB-C microphone", isConnected: true),
        AudioInput(name: "AirPods", isConnected: false),
    ]
    static let formats = ["Linear PCM", "AAC"]
}

@Observable
final class CaptureModel {
    var mode: CaptureMode
    var lut: LUTChoice
    var isRecording: Bool
    var selectedReadout: Readout?
    var autoReadouts: Set<Readout> = [.wb]
    var sheet: Sheet?
    var lens = Lens.main
    var record = RecordSettings.initial
    var photo = PhotoSettings()
    var monitor = MonitorSettings()
    var audio = AudioSettings()
    var recordingStart: Date?
    private var indices: [Readout: Int] = [.shutter: 2, .iso: 6, .wb: 5, .tint: 4, .ev: 4]

    let capabilities = RecordCapabilities.fixture
    let meterLevels = [0.62, 0.54]

    private static let ladders: [Readout: [String]] = [
        .shutter: ["1/30", "1/48", "1/60", "1/96", "1/120", "1/250", "1/500", "1/1000"],
        .iso: ["100", "125", "160", "200", "250", "320", "400", "500", "640", "800", "1000", "1250", "1600", "2000", "2500", "3200"],
        .wb: ["3200K", "3600K", "4000K", "4500K", "5000K", "5600K", "6500K", "7500K"],
        .tint: ["-8", "-6", "-4", "-2", "0", "+2", "+4", "+6", "+8"],
        .ev: ["-2.0", "-1.5", "-1.0", "-0.5", "0.0", "+0.5", "+1.0", "+1.5", "+2.0"],
    ]

    init(config: LaunchConfig) {
        mode = config.mode
        lut = config.isLutOn ? .log2 : .off
        isRecording = config.isRecording
        recordingStart = config.isRecording ? Date().addingTimeInterval(-42) : nil
        switch config.screen {
        case .main: break
        case .ruler: selectedReadout = .iso
        case .record: sheet = .record
        case .monitor: sheet = .monitor
        case .audio: sheet = .audio
        }
    }

    // MARK: Readouts

    func ladder(for readout: Readout) -> [String] {
        if readout == .fps {
            return capabilities.chips(.frameRate, for: record).filter(\.isAvailable).map(\.id)
        }
        return Self.ladders[readout] ?? []
    }

    func index(of readout: Readout) -> Int {
        if readout == .fps { return ladder(for: .fps).firstIndex(of: String(record.frameRate)) ?? 0 }
        return indices[readout] ?? 0
    }

    func setIndex(_ index: Int, of readout: Readout) {
        autoReadouts.remove(readout)
        if readout == .fps {
            if let rate = ladder(for: .fps)[safe: index].flatMap({ Int($0) }) {
                var s = record
                s.frameRate = rate
                record = capabilities.settled(s, from: record)
            }
        } else {
            indices[readout] = index
        }
    }

    func value(of readout: Readout) -> String {
        ladder(for: readout)[safe: index(of: readout)] ?? ""
    }

    func toggleSelection(_ readout: Readout) {
        guard readout.isAdjustable else { return }
        selectedReadout = selectedReadout == readout ? nil : readout
    }

    // MARK: Record settings

    func select(_ row: RecordRow, id: String) {
        var s = record
        switch row {
        case .codec: if let v = Codec(rawValue: id) { s.codec = v }
        case .quality: s.quality = id
        case .resolution: if let v = Resolution(rawValue: id) { s.resolution = v }
        case .frameRate: if let v = Int(id) { s.frameRate = v }
        case .colour: if let v = ColourSpace(rawValue: id) { s.colour = v }
        }
        record = capabilities.settled(s, from: record)
    }

    func selectedID(_ row: RecordRow) -> String {
        switch row {
        case .codec: record.codec.rawValue
        case .quality: record.quality
        case .resolution: record.resolution.rawValue
        case .frameRate: String(record.frameRate)
        case .colour: record.colour.rawValue
        }
    }

    var summaryParts: [String] { mode == .video ? record.summaryParts : photo.summaryParts }

    var remainingText: String { "\(capabilities.minutesLeft(for: record)) min" }

    func toggleRecording() {
        isRecording.toggle()
        recordingStart = isRecording ? Date() : nil
    }
}
