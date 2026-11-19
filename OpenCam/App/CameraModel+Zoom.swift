import Foundation

/// Pinch to zoom within the current lens. The rules are `PinchZoom`'s; this guards a pinch, keeps the live factor for the strip's
/// label and sends it to the session one at a time. A pinch never configures the session, raises `isViewfinderChanging` or changes
/// `manual`, and works while recording.
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

    /// `start` is the pinch when the fingers went down; `magnification` is the recognizer's scale since then.
    func setPinch(magnification: Double, from start: Double) {
        guard canPinch else { return }
        let factor = PinchZoom.factor(from: start, magnification: magnification)
        guard factor != pinch else { return }
        pinch = factor
        sendZoom(factor)
    }

    /// `-zoom <factor>`: the Simulator starts with a pinch on, for screenshots and tap checks. Only the model and the label change.
    func applyLaunchPinch(_ factor: Double?) {
        guard isSimulator, let factor else { return }
        pinch = factor
    }

    // MARK: Sending

    /// Starts a send when none runs; a running one leaves this factor waiting in place of any earlier one. Without a session
    /// (the Simulator) only the model changes.
    private func sendZoom(_ factor: Double) {
        guard let configurator, let job = zoomApplies.request(factor) else { return }
        Task { await runZoomApplies(from: job.value, on: configurator) }
    }

    /// Sends the factor, then the latest one that waited meanwhile, until none waits. The session's answer (its format may stop
    /// short of the cap) is adopted only when nothing newer was asked and the model still shows what was sent. If a configure
    /// reset the pinch while a send was in flight the send may have landed after it, so the session is told the model's pinch.
    private func runZoomApplies(from first: Double, on configurator: any SessionConfigurator) async {
        var factor: Double? = first
        while let current = factor {
            let held = await configurator.applyZoom(pinch: current)
            if let waiting = zoomApplies.finish() {
                factor = waiting.value
            } else if pinch == current {
                pinch = held
                factor = nil
            } else {
                factor = zoomApplies.request(pinch)?.value
            }
        }
    }
}
