import AVFoundation

nonisolated extension RawSizeCheckRun {
    /// One trial on a running rig: sets the size (and ProRAW when asked), reads what the output offers, takes one photo when the
    /// output offers what the request needs, and records the trial. Returns true when the capture timed out, which means the
    /// rig can no longer be trusted and the caller makes a new one.
    @discardableResult
    nonisolated(nonsending) func trial(_ route: RawSizeCheckRoute, camera: RawSizeCheckCamera, rig: RawSizeCheckRig, kind: RawSizeCheckKind,
               size: RawSizeCheckSize, enablesProRAW: Bool = false) async -> Bool {
        var trial = RawSizeCheckTrial(route: route, camera: camera.name, deviceType: camera.device.deviceType.rawValue,
                                      format: RawSizeCheckFormatFacts(camera.device.activeFormat), sessionPreset: rig.presetName,
                                      requestedMaxPhotoDimensions: size)
        if isOverBudget {
            trial.outcome = .budget
            trial.skipReason = "[RawSizeCheck:trial] The time budget is used up — {budget: \(Self.timeBudget)}"
            await record(trial)
            return false
        }
        var isTimedOut = false
        do throws(RawSizeCheckFailure) {
            try await rig.setMaxPhotoDimensions(size)
            if enablesProRAW { try await rig.setProRAW(true) }
            let availability = rig.availability()
            trial.availability = availability
            if kind == .proRAW {
                guard availability.rawPixelFormats.contains(where: { $0.kind == "proRAW" }) else {
                    throw RawSizeCheckFailure("trial", "No ProRAW format is offered", context: "size: \(size.label)", outcome: .refused)
                }
            } else {
                guard availability.hasBayer else {
                    throw RawSizeCheckFailure("trial", "No Bayer RAW format is offered", context: "size: \(size.label), formats: \(availability.rawPixelFormats.map(\.code))", outcome: .refused)
                }
            }
            let capture = try await rig.capture(kind: kind, size: size, timeout: Self.captureTimeout)
            isTimedOut = capture.isTimedOut
            trial.capture = capture
        } catch {
            trial.outcome = error.outcome
            trial.skipReason = error.message
            if error.outcome == .unsafe { trial.failedPrecondition = error.description }
        }
        if enablesProRAW, rig.output.isAppleProRAWEnabled {
            do throws(RawSizeCheckFailure) {
                try await rig.setProRAW(false)
            } catch {
                addError("trial", "ProRAW could not be turned off again", context: error.message)
            }
        }
        await record(trial)
        return isTimedOut
    }

    /// A trial that could not start at all, with the camera's own format when it has one.
    nonisolated(nonsending) func skippedTrial(_ route: RawSizeCheckRoute, camera: RawSizeCheckCamera, size: RawSizeCheckSize?,
                                              outcome: RawSizeCheckOutcome, reason: String) async {
        let trial = RawSizeCheckTrial(route: route, camera: camera.name, deviceType: camera.device.deviceType.rawValue,
                                      format: RawSizeCheckFormatFacts(camera.device.activeFormat), sessionPreset: "none",
                                      requestedMaxPhotoDimensions: size, outcome: outcome, skipReason: reason)
        await record(trial)
    }

    /// A trial that did not start because the time budget ran out before a rig could be built or a format switched.
    nonisolated(nonsending) func budgetTrial(_ route: RawSizeCheckRoute, camera: RawSizeCheckCamera, size: RawSizeCheckSize?) async {
        await skippedTrial(route, camera: camera, size: size, outcome: .budget,
                           reason: "[RawSizeCheck:budgetTrial] The time budget is used up — {budget: \(Self.timeBudget), camera: \(camera.name)}")
    }
}
