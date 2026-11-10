import SwiftUI

struct TimecodeReadout: View {
    let model: CameraModel
    var isCompact = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30)) { timeline in
            ReadoutView(caption: "TIMECODE", value: timecode(at: timeline.date), isAlert: model.isRecording, showsIndicator: model.isRecording, isCompact: isCompact)
        }
    }

    private func timecode(at date: Date) -> String {
        let elapsed = model.recordingStart.map { max(0, date.timeIntervalSince($0)) } ?? 0
        let frames = Int(elapsed * 30)
        return String(format: "%02d:%02d:%02d:%02d", frames / 108_000, frames / 1_800 % 60, frames / 30 % 60, frames % 30)
    }
}
