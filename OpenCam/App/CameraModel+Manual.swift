import Foundation

/// Setting the camera by hand: what is open, what is set, and how it reaches the session. Nothing here configures the
/// session, raises the viewfinder blur, or saves.
extension CameraModel {
    static let controlFailedNotice = "That setting could not be applied."
    /// The device reports floats; a bias this close to the one applied is that one.
    static let biasTolerance: Float = 0.01

    /// A configure that was requested but has not run yet; the session's ranges may belong to the camera before it.
    var isConfigurePending: Bool { requestedConfiguration != lastWorking?.configuration }

    /// With a camera, away from the sweep, a scan and the Library, and with no configure waiting.
    var canAdjustControls: Bool {
        hasCamera && !isSweeping && !isScanningFormats && !isLibraryPresented && !isConfigurePending
    }

    func scale(for control: ManualControl) -> ManualScale? {
        guard let manualRanges else { return nil }
        return ManualScale.make(for: control, ranges: manualRanges)
    }

    /// The number the readout and the thumb show: the hand-set value, else the camera's.
    private func shownValue(of control: ManualControl) -> Double? {
        hasCamera ? manual.value(of: control, live: shownReadouts) : nil
    }

    /// The same text the readouts show.
    func readoutText(for control: ManualControl) -> String {
        control.text(shownValue(of: control))
    }

    func readout(for control: ManualControl) -> ControlReadoutState {
        let value = shownValue(of: control)
        return ControlReadoutState(
            text: control.text(value),
            spoken: control.spoken(value),
            isSet: manual.isSet(control),
            isOpen: openControl == control,
            isAvailable: canAdjustControls && manual.isAdjustable(control) && scale(for: control) != nil
        )
    }

    var openSlider: OpenSlider? {
        guard let control = openControl, manual.isAdjustable(control), let scale = scale(for: control) else { return nil }
        let value = shownValue(of: control)
        return OpenSlider(
            control: control,
            stepCount: scale.values.count,
            step: value.map { scale.step(nearest: $0) },
            adjustStride: scale.adjustStride,
            text: control.text(value),
            spoken: control.spoken(value),
            isAutomatic: !manual.isSet(control)
        )
    }

    /// Opens the slider, switches to this one, or closes it when it is the open one. Changes nothing on the camera.
    func toggleControl(_ control: ManualControl) {
        if openControl == control {
            closeControl()
            return
        }
        guard canAdjustControls, manual.isAdjustable(control), scale(for: control) != nil else { return }
        openControl = control
    }

    func closeControl() {
        guard openControl != nil else { return }
        openControl = nil
    }

    /// Moves `control` to `step` of its scale (clamped to it) and sends the whole setting to the session.
    func setControl(_ control: ManualControl, step: Int) {
        guard canAdjustControls, manual.isAdjustable(control), let scale = scale(for: control) else { return }
        let target = scale.step(step, movedBy: 0)
        if let value = shownValue(of: control), scale.crossesDetent(from: scale.step(nearest: value), to: target) {
            controlStepped()
        }
        manual = manual.setting(control, to: scale.values[target], live: shownReadouts)
        sendManual()
    }

    /// Hands `control` (and the one it is locked with) back to the camera. EV has no Auto.
    func setAutomatic(_ control: ManualControl) {
        guard control.hasAutomatic, canAdjustControls else { return }
        let next = manual.settingAutomatic(control)
        guard next != manual else { return }
        manual = next
        sendManual()
    }

    /// The camera is changing, or is not usable: the slider closes, the values return to automatic and are sent, and an apply
    /// that began earlier changes nothing when it returns. Ranges are the new camera's to report on the next poll (the
    /// Simulator's are simulated at once).
    func resetManual() {
        manualGeneration += 1
        openControl = nil
        appliedManual = .automatic
        reappliesAllManual = false
        if !seedSimulatedCamera() { manualRanges = nil }
        guard manual != .automatic else { return }
        manual = .automatic
        sendManual()
    }

    /// After an interruption: the camera may have dropped what was set, so every group is sent again.
    func reapplyAllManual() {
        guard manual != .automatic else { return }
        reappliesAllManual = true
        sendManual()
    }

    /// The Camera Control writes the same device bias. While the app's own apply is not running, a live bias that is not the
    /// one the app applied was set there: the app lets go of its own, so the readout shows the camera and a later re-apply
    /// cannot write the app's stale bias over it.
    func followCameraControlBias(live: Float?) {
        guard let applied = appliedManual.bias, let live, abs(live - applied) > Self.biasTolerance else { return }
        manual.bias = nil
        appliedManual.bias = nil
    }

    /// Takes new ranges from the session. The open control closes when its scale is gone.
    func adoptRanges(_ ranges: ManualRanges?) {
        if ranges != manualRanges { manualRanges = ranges }
        if let control = openControl, scale(for: control) == nil { openControl = nil }
    }

    // MARK: Sending

    /// Starts an apply when none runs; a running one leaves this snapshot waiting in place of any earlier one.
    private func sendManual() {
        guard let configurator, let job = manualApplies.request(manual) else { return }
        manualApplyTask = Task { await runManualApplies(from: job, on: configurator) }
    }

    /// Applies the job, then the latest snapshot that waited meanwhile, until none waits.
    private func runManualApplies(from first: (generation: Int, value: ManualSettings), on configurator: any SessionConfigurator) async {
        var job: (generation: Int, value: ManualSettings)? = first
        while let current = job {
            let generation = manualGeneration
            let reapplyingAll = reappliesAllManual
            reappliesAllManual = false
            do throws(ManualControlError) {
                let applied = try await configurator.applyManual(current.value, reapplyingAll: reapplyingAll)
                if generation == manualGeneration { manualApplied(applied, sent: current.value) }
            } catch {
                if reapplyingAll { reappliesAllManual = true }
                manualApplyFailed(error, sent: current.value, generation: generation)
            }
            job = manualApplies.finish()
        }
    }

    /// What the session set is what the camera has; the model takes it unless the user has moved on.
    private func manualApplied(_ applied: ManualSettings, sent: ManualSettings) {
        appliedManual = applied
        if manual == sent, applied != sent { manual = applied }
        clearNotice(from: .control)
    }

    /// The model returns to what the camera has, unless the user has moved on (the snapshot that waits then decides).
    private func manualApplyFailed(_ error: ManualControlError, sent: ManualSettings, generation: Int) {
        Self.logger.error("\(error.description, privacy: .public)")
        ErrorJournal.record(error.description)
        guard generation == manualGeneration else { return }
        if manual == sent { manual = appliedManual }
        if error != .noCamera { show(Self.controlFailedNotice, from: .control) }
    }
}
