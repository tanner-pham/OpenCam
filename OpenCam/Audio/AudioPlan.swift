import Foundation

/// What the audio session should look like. The default plan is today's behaviour: the capture session configures audio and
/// nothing is pinned or monitored, and going from one default plan to another takes no steps.
nonisolated struct AudioPlan: Equatable, Sendable {
    var pin: AudioPin? = nil
    var captureConfiguresAudio = true
    var isMonitoring = false

    /// The device calls that take what was `applied` to this plan. The monitor stops first and starts last. Taking over audio
    /// from the capture session turns its flag off, then sets the input, and sets it again every time. Handing back clears
    /// the input only when this plan has none, then turns the flag on.
    func steps(from applied: AudioPlan) -> [AudioStep] {
        var steps: [AudioStep] = []
        if captureConfiguresAudio {
            if pin == nil, applied.pin != nil { steps.append(.clearPin) }
            if !applied.captureConfiguresAudio { steps.append(.captureConfiguresAudio(true)) }
        } else {
            let isTakingOver = applied.captureConfiguresAudio
            if isTakingOver { steps.append(.captureConfiguresAudio(false)) }
            if let pin, isTakingOver || applied.pin != pin { steps.append(.pin(pin)) }
        }
        // A running monitor is rebuilt when the input under it changes.
        let isRestarting = applied.isMonitoring && isMonitoring && !steps.isEmpty
        if applied.isMonitoring, !isMonitoring || isRestarting { steps.insert(.stopMonitor, at: 0) }
        if isMonitoring, !applied.isMonitoring || isRestarting { steps.append(.startMonitor) }
        return steps
    }
}
