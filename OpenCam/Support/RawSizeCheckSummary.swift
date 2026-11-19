/// The answer: the largest RAW any trial delivered, and who delivered it.
nonisolated struct RawSizeCheckSummary: Codable, Sendable, Equatable {
    var largestRawSize: RawSizeCheckSize?
    var route: RawSizeCheckRoute?
    var camera: String?
    var format: String?
    var trialCount: Int
    /// Trials that made a photo request.
    var ranCount: Int
    /// Trials the phone did not offer.
    var refusedCount: Int
    /// Trials held back because a precondition of a safe request did not hold.
    var unsafeCount: Int
    /// Trials cut by the time budget.
    var budgetCount: Int
    /// Trials that delivered a RAW photo.
    var rawDeliveredCount: Int
    var sentence: String

    /// The first trial to deliver the largest size wins a tie. A RAW counts with the size ImageIO read from its data, or, when
    /// ImageIO could not read it, with the size the resolved settings reported.
    static func make(from trials: [RawSizeCheckTrial]) -> RawSizeCheckSummary {
        func count(_ outcome: RawSizeCheckOutcome) -> Int { trials.filter { $0.outcome == outcome }.count }
        var best: (trial: RawSizeCheckTrial, size: RawSizeCheckSize)?
        var delivered = 0
        for trial in trials {
            guard let size = trial.deliveredRawSize else { continue }
            delivered += 1
            if size.pixels > (best?.size.pixels ?? 0) { best = (trial, size) }
        }
        let counts = "\(count(.ran)) trials ran, \(count(.refused)) were refused by the phone, \(count(.unsafe)) were held back as unsafe, \(count(.budget)) were cut by the time budget."
        var sentence: String
        if let best {
            if best.size.pixels > RawSizeCheckSize.twelveMegapixel.pixels {
                sentence = "\(best.trial.route.shortTitle) on the \(best.trial.camera) camera delivered \(best.size.label) with format \(best.trial.format.description)"
            } else {
                sentence = "No route delivered a RAW larger than \(best.size.label)"
            }
            let measured = best.trial.measuredRawSize
            let resolved = best.trial.capture?.resolvedRawPhotoDimensions
            if measured != resolved {
                sentence += " (DNG data: \(measured?.label ?? "unreadable"); resolved settings: \(resolved?.label ?? "not reported"))"
            }
            sentence += "."
        } else {
            sentence = "No trial delivered a RAW photo."
        }
        return RawSizeCheckSummary(largestRawSize: best?.size, route: best?.trial.route, camera: best?.trial.camera,
                                   format: best?.trial.format.description, trialCount: trials.count, ranCount: count(.ran),
                                   refusedCount: count(.refused), unsafeCount: count(.unsafe), budgetCount: count(.budget),
                                   rawDeliveredCount: delivered, sentence: "\(sentence) \(counts)")
    }
}
