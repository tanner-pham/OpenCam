import Foundation

/// One option of a format sweep: what was asked for, what the file contains, and whether they agree.
nonisolated struct SweepRow: Codable, Sendable, Equatable {
    /// Each clip records this long.
    static let clipSeconds = 3
    /// A clip shorter than this fails; a recording takes a moment to begin, so a 3 s clip comes out a little short.
    static let minimumSeconds = 2.5
    /// The file's nominal frame rate may differ from the request by this much.
    static let frameRateTolerance = 0.5
    static let recordingFailed = "Recording failed."
    static let didNotFinish = "The clip did not finish."

    let requested: VideoOption
    let actual: ClipFacts?
    let status: SweepStatus
    /// Plain failure text, the only text SweepView shows.
    let error: String?
    /// The raw error description, kept in the report file only, never on screen.
    let detail: String?
    /// True for a step that passed its deadline; reports written before this field read as false.
    var isTimedOut = false
    /// False when the camera was interrupted or stopped while the row ran; such a row says nothing about the option.
    /// Reports written before this field read as true.
    var wasCameraUsable = true

    /// Fails on the first of: a recording error, an unreadable clip, codec, dimensions (either orientation), frame rate,
    /// colour (only when the file reports one), duration. Dropped frames stay in `actual` and never fail a row.
    static func evaluate(requested: VideoOption, facts: ClipFacts?, error: String?) -> SweepRow {
        if let error {
            return SweepRow(requested: requested, actual: facts, status: .fail, error: recordingFailed, detail: error)
        }
        guard let facts else {
            return SweepRow(requested: requested, actual: nil, status: .fail, error: recordingFailed, detail: nil)
        }
        let reason = mismatch(requested: requested, facts: facts)
        return SweepRow(requested: requested, actual: facts, status: reason == nil ? .pass : .fail, error: reason, detail: nil)
    }

    /// False for a row that passed its deadline, or that ran while the camera was unusable: it says nothing about
    /// whether the option works.
    var hasAnswer: Bool { !isTimedOut && wasCameraUsable }

    /// This row, marked as recorded while the camera was unusable.
    func recordedWithoutCamera() -> SweepRow {
        var row = self
        row.wasCameraUsable = false
        return row
    }

    /// A step that passed its deadline; `detail` names the step.
    static func timedOut(requested: VideoOption, detail: String) -> SweepRow {
        SweepRow(requested: requested, actual: nil, status: .fail, error: didNotFinish, detail: detail, isTimedOut: true)
    }

    private static func mismatch(requested: VideoOption, facts: ClipFacts) -> String? {
        let asked = requested.resolution
        if facts.codecFourCC != requested.codec.codecType {
            return "Asked for \(requested.codec.codecType), file has \(facts.codecFourCC)."
        }
        let isSameSize = (facts.width == asked.width && facts.height == asked.height)
            || (facts.width == asked.height && facts.height == asked.width)
        if !isSameSize {
            return "Asked for \(asked.width) x \(asked.height), file has \(facts.width) x \(facts.height)."
        }
        if abs(facts.nominalFrameRate - Double(requested.frameRate)) > frameRateTolerance {
            return "Asked for \(requested.frameRate) fps, file has \(oneDecimal(facts.nominalFrameRate)) fps."
        }
        if let colour = facts.colour, colour != requested.colour {
            return "Asked for \(requested.colour.rawValue), file has \(colour.rawValue)."
        }
        if facts.durationSeconds < minimumSeconds {
            return "Clip is \(oneDecimal(facts.durationSeconds)) s, expected \(clipSeconds) s."
        }
        return nil
    }

    /// Always a full stop as the decimal mark, whatever the locale.
    private static func oneDecimal(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}

nonisolated extension SweepRow {
    /// Decodes reports written before `isTimedOut` and `wasCameraUsable` existed.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        requested = try container.decode(VideoOption.self, forKey: .requested)
        actual = try container.decodeIfPresent(ClipFacts.self, forKey: .actual)
        status = try container.decode(SweepStatus.self, forKey: .status)
        error = try container.decodeIfPresent(String.self, forKey: .error)
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
        isTimedOut = try container.decodeIfPresent(Bool.self, forKey: .isTimedOut) ?? false
        wasCameraUsable = try container.decodeIfPresent(Bool.self, forKey: .wasCameraUsable) ?? true
    }
}
