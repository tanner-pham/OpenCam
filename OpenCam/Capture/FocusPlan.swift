import Foundation

/// What to set on the camera for a request. A group set by hand (focus, or shutter and ISO) is never in the plan, so a tap
/// never undoes what the sliders set. The session only forwards each field that is present.
nonisolated struct FocusPlan: Sendable, Equatable {
    enum Mode: Sendable, Equatable { case once, continuous }

    /// Both nil: focus is left as it is.
    var focusPoint: FocusPoint?
    var focusMode: Mode?
    /// Both nil: exposure is left as it is.
    var exposurePoint: FocusPoint?
    var exposureMode: Mode?
    var watchesSubjectArea: Bool
    var outcome: FocusOutcome

    /// `manual` nil counts as automatic.
    static func make(_ request: FocusRequest, manual: ManualSettings?, support: FocusSupport) -> FocusPlan {
        let target: FocusPoint
        let wantsOnce: Bool
        switch request {
        case .point(let point), .lock(let point): (target, wantsOnce) = (point, true)
        case .recentre: (target, wantsOnce) = (.centre, false)
        }
        var plan = FocusPlan(watchesSubjectArea: false, outcome: .nothing)
        if manual?.focus == nil, support.focusPoint,
           let mode = mode(once: wantsOnce && support.autoFocusOnce, continuous: support.continuousFocus) {
            plan.focusPoint = target
            plan.focusMode = mode
        }
        if (manual?.exposure ?? .automatic) == .automatic, support.exposurePoint,
           let mode = mode(once: wantsOnce && support.autoExposeOnce, continuous: support.continuousExposure) {
            plan.exposurePoint = target
            plan.exposureMode = mode
        }
        switch (plan.focusMode != nil, plan.exposureMode != nil) {
        case (true, true): plan.outcome = .focusAndExposure
        case (false, true): plan.outcome = .exposureOnly
        case (true, false): plan.outcome = .focusOnly
        case (false, false): plan.outcome = .nothing
        }
        if case .point = request, plan.outcome != .nothing { plan.watchesSubjectArea = true }
        return plan
    }

    private static func mode(once: Bool, continuous: Bool) -> Mode? {
        if once { return .once }
        return continuous ? .continuous : nil
    }
}
