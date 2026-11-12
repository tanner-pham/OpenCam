import SwiftUI

struct TimecodeReadout: View {
    let model: CameraModel
    var isCompact = false

    var body: some View {
        // Ticks only while recording; idle, the schedule is paused and nothing redraws. Red on the compact bar's glass over the
        // picture is unreadable (about 1.2:1), so there the text stays primary and the red dot alone marks the recording.
        TimelineView(.animation(minimumInterval: 1.0 / Double(model.timecodeFrameRate), paused: !model.isRecording)) { timeline in
            ReadoutView(caption: "TIMECODE", value: timecode(at: timeline.date), isAlert: model.isRecording && !isCompact, showsIndicator: model.isRecording, isCompact: isCompact)
        }
    }

    private func timecode(at date: Date) -> String {
        let elapsed = model.recordingStart.map { date.timeIntervalSince($0) } ?? 0
        return Timecode.string(elapsed: elapsed, frameRate: model.timecodeFrameRate)
    }
}
