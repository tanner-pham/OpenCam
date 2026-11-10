import SwiftUI

struct TimecodeReadout: View {
    let model: CameraModel
    var isCompact = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / Double(model.timecodeFrameRate))) { timeline in
            ReadoutView(caption: "TIMECODE", value: timecode(at: timeline.date), isAlert: model.isRecording, showsIndicator: model.isRecording, isCompact: isCompact)
        }
    }

    private func timecode(at date: Date) -> String {
        let elapsed = model.recordingStart.map { date.timeIntervalSince($0) } ?? 0
        return Timecode.string(elapsed: elapsed, frameRate: model.timecodeFrameRate)
    }
}
