import SwiftUI

/// The camera's capture feedback: the shutter blink's trigger and the change blur's flag for the viewfinder below, and a haptic for each event. A light
/// impact for a photo, the system's start and stop for a recording (`SensoryFeedback.start` and `.stop`, iOS 17). The system
/// already plays its own shutter and record sounds, so none is added. Only this modifier reads `feedback`, so an event re-runs
/// its body and not the screen's.
struct CaptureFeedbackModifier: ViewModifier {
    let model: CameraModel

    func body(content: Content) -> some View {
        let feedback = model.feedback
        content
            .environment(\.shutterBlinks, feedback.photosTaken)
            .environment(\.isViewfinderChanging, model.isViewfinderChanging)
            .sensoryFeedback(.impact(weight: .light), trigger: feedback.photosTaken)
            .sensoryFeedback(.start, trigger: feedback.recordingsStarted)
            .sensoryFeedback(.stop, trigger: feedback.recordingsStopped)
            .sensoryFeedback(.selection, trigger: feedback.controlSteps)
    }
}
