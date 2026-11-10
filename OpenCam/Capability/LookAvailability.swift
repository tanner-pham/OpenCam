import Foundation

/// When the camera offers a look, and the words around that. A look is a Rec. 709 or P3 picture, so a video format in
/// HLG or a log colour space has none; a photo always can.
nonisolated enum LookAvailability {
    static let noneID = "none"
    static let needsSDR = "Looks need Rec. 709 or P3."
    static let videoPreviewOnly = "Shown in the viewfinder only. Video is recorded without it."
    static let turnedOff = "Look turned off. Looks need Rec. 709 or P3."
    static let summaryNameLimit = 16

    static func isOffered(mode: CaptureMode, colour: ColourMode) -> Bool {
        switch mode {
        case .photo: true
        case .video: colour == .rec709 || colour == .p3
        }
    }

    /// "None" first, then each look. When looks are not offered they are dimmed with the reason; None stays available.
    static func chips(looks: [Look], isOffered: Bool) -> [Chip] {
        let none = Chip(id: noneID, title: "None", detail: nil, isAvailable: true, reason: nil)
        return [none] + looks.map {
            Chip(id: $0.id.uuidString, title: $0.name, detail: nil, isAvailable: isOffered, reason: isOffered ? nil : needsSDR)
        }
    }

    static func reasonLine(mode: CaptureMode, isOffered: Bool, hasLook: Bool) -> String? {
        if !isOffered { return needsSDR }
        return mode == .video && hasLook ? videoPreviewOnly : nil
    }

    /// The summary button cannot truncate, so a long name is cut here.
    static func summaryName(_ name: String) -> String {
        guard name.count > summaryNameLimit else { return name }
        return String(name.prefix(summaryNameLimit - 1)) + "…"
    }
}
