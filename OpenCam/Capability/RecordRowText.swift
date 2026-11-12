import Foundation

/// The wording around ProRes, Log and Apple Log in Record settings.
nonisolated enum RecordRowText {
    static let logDetail = "baked curve"
    static let logNote = "Log records a flat picture made from HLG, for grading later. The curve cannot be removed from the file. The viewfinder shows the normal picture."
    static let appleLogUnavailable = "This iPhone does not record Apple Log, Apple Log 2 or RAW video."
    static let proResNote = "The camera delivers 4:2:0 colour. ProRes stores it in a 4:2:2 file and adds no colour detail."
    static let proResSDRNote = "The camera delivers 8-bit 4:2:0 colour in Rec. 709. ProRes stores it in a 10-bit 4:2:2 file and adds no detail."

    private static let appleLogID = ColourMode.appleLog.rawValue

    /// A row's chips as shown. Colour: Log carries `logDetail`; when no chip is Apple Log or Apple Log 2, a dimmed "Apple Log"
    /// chip with `appleLogUnavailable` is added last.
    static func chips(_ row: RecordRow, from chips: [Chip]) -> [Chip] {
        guard row == .colour else { return chips }
        var shown = chips.map { chip in
            chip.id == ColourMode.log.rawValue
                ? Chip(id: chip.id, title: chip.title, detail: logDetail, isAvailable: chip.isAvailable, reason: chip.reason, estimate: chip.estimate)
                : chip
        }
        let hasAppleLog = shown.contains { $0.id == ColourMode.appleLog.rawValue || $0.id == ColourMode.appleLog2.rawValue }
        if !hasAppleLog {
            shown.append(Chip(id: appleLogID, title: appleLogID, detail: nil, isAvailable: false, reason: appleLogUnavailable))
        }
        return shown
    }

    /// The one line under a row: Colour with Log selected, `logNote`; Quality with ProRes selected, `proResNote` or
    /// `proResSDRNote`; otherwise the first dimmed chip's reason.
    static func line(_ row: RecordRow, chips: [Chip], selection: RecordSelection) -> String? {
        switch row {
        case .colour where selection.colour == .log:
            return logNote
        case .quality where selection.family == .proRes:
            return selection.colour == .rec709 ? proResSDRNote : proResNote
        default:
            return chips.first { !$0.isAvailable }?.reason
        }
    }
}

nonisolated extension CaptureCapabilities {
    /// What the phone's own scan holds: no ProRes, no RAW, no Apple Log colours, and no writer options. For checking the
    /// Record settings the phone shows in the Simulator.
    func asThePhoneScans() -> CaptureCapabilities {
        var scanned = self
        scanned.videoOptions = videoOptions.filter {
            $0.codec.family != .proRes && $0.codec.family != .raw && $0.colour != .appleLog && $0.colour != .appleLog2
        }
        scanned.writerOptions = []
        return scanned
    }
}
