/// The answer: the largest RAW any trial delivered, and who delivered it.
nonisolated struct RawSizeCheckSummary: Codable, Sendable, Equatable {
    var largestRawSize: RawSizeCheckSize?
    var route: RawSizeCheckRoute?
    var camera: String?
    var format: String?
    var trialCount: Int
    var skippedCount: Int
    var rawDeliveredCount: Int
    var sentence: String

    /// The first trial to deliver the largest size wins a tie.
    static func make(from trials: [RawSizeCheckTrial]) -> RawSizeCheckSummary {
        let skipped = trials.filter { $0.skipReason != nil }.count
        var best: (trial: RawSizeCheckTrial, size: RawSizeCheckSize)?
        var delivered = 0
        for trial in trials {
            guard let size = trial.deliveredRawSize else { continue }
            delivered += 1
            if size.pixels > (best?.size.pixels ?? 0) { best = (trial, size) }
        }
        guard let best else {
            return RawSizeCheckSummary(largestRawSize: nil, route: nil, camera: nil, format: nil, trialCount: trials.count,
                                       skippedCount: skipped, rawDeliveredCount: 0, sentence: "No trial delivered a RAW photo.")
        }
        let sentence: String
        if best.size.pixels > RawSizeCheckSize.twelveMegapixel.pixels {
            sentence = "\(best.trial.route.shortTitle) on the \(best.trial.camera) camera delivered \(best.size.label) with format \(best.trial.format.description)."
        } else {
            sentence = "No route delivered a RAW larger than \(best.size.label)."
        }
        return RawSizeCheckSummary(largestRawSize: best.size, route: best.trial.route, camera: best.trial.camera,
                                   format: best.trial.format.description, trialCount: trials.count, skippedCount: skipped,
                                   rawDeliveredCount: delivered, sentence: sentence)
    }
}
