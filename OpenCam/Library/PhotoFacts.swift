import Foundation
import ImageIO

/// The lens and exposure facts a photo's Exif carries. A fact the file does not carry stays nil.
nonisolated struct PhotoFacts: Sendable, Equatable {
    var lensModel: String?
    var focalLength: Double?
    var equivalentFocalLength: Int?
    var aperture: Double?
    var exposureTime: Double?
    var iso: Int?

    static let none = PhotoFacts()

    /// Exif of image 0; a missing file, no Exif, or a value that is absent, not a number or not above 0 leaves that fact nil.
    @concurrent static func read(at url: URL) async -> PhotoFacts {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        else { return .none }
        func number(_ key: CFString) -> Double? {
            guard let value = exif[key] as? Double, value > 0 else { return nil }
            return value
        }
        var facts = PhotoFacts()
        if let model = exif[kCGImagePropertyExifLensModel] as? String, !model.isEmpty { facts.lensModel = model }
        facts.focalLength = number(kCGImagePropertyExifFocalLength)
        facts.equivalentFocalLength = (exif[kCGImagePropertyExifFocalLenIn35mmFilm] as? Int).flatMap { $0 > 0 ? $0 : nil }
        facts.aperture = number(kCGImagePropertyExifFNumber)
        facts.exposureTime = number(kCGImagePropertyExifExposureTime)
        facts.iso = (exif[kCGImagePropertyExifISOSpeedRatings] as? [Int])?.first.flatMap { $0 > 0 ? $0 : nil }
        return facts
    }

    /// 1.8 "f/1.8", 2.0 "f/2".
    static func apertureText(_ f: Double) -> String { "f/" + oneDecimal(f) }

    /// Below 1 second "1/<round(1/t)> s"; else one decimal with ".0" dropped: "2 s", "2.5 s".
    static func shutterText(seconds: Double) -> String {
        guard seconds < 1 else { return oneDecimal(seconds) + " s" }
        return "1/\(Int((1 / seconds).rounded())) s"
    }

    /// 6.86 "6.9 mm", 24 "24 mm".
    static func millimetresText(_ mm: Double) -> String { oneDecimal(mm) + " mm" }

    private static func oneDecimal(_ value: Double) -> String {
        let text = String(format: "%.1f", value)
        return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
    }

    /// The designation, then the lens (equivalent focal length, else focal length, else lens model), aperture, shutter and ISO;
    /// present ones only.
    func summary(_ designation: FormatDesignation?) -> String {
        var parts: [String] = []
        if let designation { parts.append(designation.title) }
        if let equivalentFocalLength {
            parts.append(Self.millimetresText(Double(equivalentFocalLength)))
        } else if let focalLength {
            parts.append(Self.millimetresText(focalLength))
        } else if let lensModel {
            parts.append(lensModel)
        }
        if let aperture { parts.append(Self.apertureText(aperture)) }
        if let exposureTime { parts.append(Self.shutterText(seconds: exposureTime)) }
        if let iso { parts.append("ISO \(iso)") }
        return parts.joined(separator: " · ")
    }

    /// Format, Lens, Focal length, Equivalent focal length, Aperture, Shutter, ISO; present ones only.
    func rows(_ designation: FormatDesignation?) -> [PhotoInfoRow] {
        var rows: [PhotoInfoRow] = []
        if let designation { rows.append(PhotoInfoRow(title: "Format", value: designation.title)) }
        if let lensModel { rows.append(PhotoInfoRow(title: "Lens", value: lensModel)) }
        if let focalLength { rows.append(PhotoInfoRow(title: "Focal length", value: Self.millimetresText(focalLength))) }
        if let equivalentFocalLength {
            rows.append(PhotoInfoRow(title: "Equivalent focal length", value: Self.millimetresText(Double(equivalentFocalLength))))
        }
        if let aperture { rows.append(PhotoInfoRow(title: "Aperture", value: Self.apertureText(aperture))) }
        if let exposureTime { rows.append(PhotoInfoRow(title: "Shutter", value: Self.shutterText(seconds: exposureTime))) }
        if let iso { rows.append(PhotoInfoRow(title: "ISO", value: String(iso))) }
        return rows
    }
}
