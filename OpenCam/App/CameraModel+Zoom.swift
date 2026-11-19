import Foundation

/// Pinch to zoom within the current lens. The rules are `PinchZoom`'s; this guards a pinch, keeps the live factor for the strip's
/// label and sends it to the session one at a time, after any configure in flight. A pinch never configures the session, raises
/// `isViewfinderChanging` or changes `manual`, and works while recording.
extension CameraModel {
    /// A pinch may start: a camera to aim, and not a photo format with Bayer RAW, which captures only at a zoom of exactly 1
    /// (`PhotoSettingsPlan` refuses it otherwise, and the Camera Control's zoom is left out for those formats too). Video has no
    /// such limit.
    var canPinch: Bool {
        canAim && !(mode == .photo && currentPhotoOption?.format.includesRAW == true)
    }

    /// The strip's lens text while a pinch is on ("1.6x"); nil with no pinch or without a camera.
    var zoomLabel: String? {
        guard hasCamera, let lens = currentLens else { return nil }
        return PinchZoom.label(for: lens, pinch: pinch)
    }

    /// `start` is the pinch when the fingers went down; `magnification` is the recognizer's scale since then. Past the limit the
    /// session last reported for this configuration the factor stops there, so the label does not move.
    func setPinch(magnification: Double, from start: Double) {
        guard canPinch else { return }
        var factor = PinchZoom.factor(from: start, magnification: magnification)
        if let pinchLimit { factor = min(factor, pinchLimit) }
        guard factor != pinch else { return }
        pinch = factor
        sendZoom(factor)
    }

    /// Called for every configuration a selection change asks for: the pinch goes back to 1 unless only a look, sound, recorder
    /// or combined-camera difference separates it from the one the pinch was last decided for. That one survives the Library's
    /// release and return, which clear `requestedConfiguration`, so a visit keeps the pinch.
    func resetPinchIfNeeded(for configuration: SessionConfiguration) {
        if !PinchZoom.keeps(from: pinchConfiguration, to: configuration) { resetPinch() }
        pinchConfiguration = configuration
    }

    /// The pinch back to 1 on the model, and on the session too when it was not 1: the session may keep its own (it decides on
    /// the configurations it is given, and a configure that a later one superseded is never given), so it is told through the
    /// same queue, after the configure in flight.
    func resetPinch() {
        pinchLimit = nil
        guard pinch != 1 else { return }
        pinch = 1
        sendZoom(1)
    }

    /// `-zoom <factor>`: the Simulator starts with a pinch on when a pinch could start, for screenshots and tap checks. Only the
    /// model and the label change.
    func applyLaunchPinch(_ factor: Double?) {
        guard isSimulator, let factor else { return }
        pinchConfiguration = sessionConfiguration
        pinch = factor
    }

    // MARK: Sending

    /// Starts a send when none runs; a running one leaves this factor waiting in place of any earlier one. Without a session
    /// (the Simulator) only the model changes.
    private func sendZoom(_ factor: Double) {
        guard let configurator, let job = zoomApplies.request(factor) else { return }
        Task { await runZoomApplies(from: job.value, on: configurator) }
    }

    /// Returns once the newest queued configure has ended, also when another was queued while one was awaited.
    private func waitForConfigureChain() async {
        var waiting = configureTask
        while let task = waiting {
            _ = await task.value
            waiting = configureTask
            if waiting == task { return }
        }
    }

    /// Sends the factor, after the configure in flight (a zoom that reaches the session first would be overwritten by that
    /// configure's own, or reset by it), then the latest one that waited meanwhile, until none waits. The session's answer (its
    /// format or range may stop short of the cap) is adopted only when nothing newer was asked and the model still shows what was
    /// sent; a smaller answer is also the limit for this configuration. If the pinch changed while a send was in flight, the
    /// session is told the model's pinch.
    private func runZoomApplies(from first: Double, on configurator: any SessionConfigurator) async {
        var factor: Double? = first
        while let current = factor {
            await waitForConfigureChain()
            let held = await configurator.applyZoom(pinch: current)
            if let waiting = zoomApplies.finish() {
                factor = waiting.value
            } else if pinch == current {
                if held < current { pinchLimit = held }
                pinch = held
                factor = nil
            } else {
                factor = zoomApplies.request(pinch)?.value
            }
        }
    }
}
