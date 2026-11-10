import SwiftUI

/// The format sweep sheet: explains the sweep, starts or cancels it, shows progress, the result and each failed or
/// frame-dropping clip in plain text, and offers the capability rescan. It cannot be closed while a sweep runs.
struct SweepView: View {
    let model: CameraModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    static let bodyText = "Records 3 seconds in each video format this lens reports, then saves a report in the Captures folder."
    static let rescanTitle = "Read camera formats again"
    static let rescanCaption = "Use this if a camera or format is missing."

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    Text(model.phase == .ready ? Self.bodyText : CameraModel.sweepNeedsCamera)
                        .font(.body)
                    controls
                    if let sweep = model.sweep { progress(sweep) }
                    rescan
                        .padding(.top, Theme.Space.s)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, verticalSizeClass == .compact ? 0 : Theme.Space.l)
                .padding(.trailing, Theme.Space.l)
            }
            .navigationTitle("Format sweep")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { dismiss() }
                        .disabled(model.isSweeping)
                }
            }
        }
        .tint(Theme.accent)
        .interactiveDismissDisabled(model.isSweeping)
    }

    @ViewBuilder
    private var controls: some View {
        if model.isSweeping {
            Button("Cancel") { model.cancelSweep() }
                .buttonStyle(.glass)
                .disabled(model.sweep?.isRunning != true)
        } else {
            Button("Start") { Task { await model.startSweep() } }
                .buttonStyle(.glassProminent)
                .disabled(!model.canStartSweep)
        }
    }

    @ViewBuilder
    private func progress(_ sweep: FormatSweep) -> some View {
        if sweep.isRunning {
            ProgressView(value: Double(sweep.done), total: Double(max(sweep.total, 1)))
            Text(sweep.progressText)
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        if let resultText = sweep.resultText {
            Text(resultText)
                .font(.footnote.monospacedDigit())
        }
        ForEach(Array(sweep.rows.enumerated()), id: \.offset) { _, row in
            if let note = Self.note(for: row) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(Self.title(of: row.requested))
                        .font(.footnote.weight(.semibold))
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(row.status == .fail ? Theme.recordRed : .secondary)
                }
            }
        }
    }

    private var rescan: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Button(Self.rescanTitle) { Task { await model.rescanCapabilities() } }
                .buttonStyle(.glass)
                .disabled(!model.canRescanCapabilities || model.isSweeping)
            Text(Self.rescanCaption)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    /// "HEVC High, 4K, 30 fps, Rec. 709"
    static func title(of option: VideoOption) -> String {
        "\(option.codec.displayName), \(option.resolution.label), \(option.frameRate) fps, \(option.colour.rawValue)"
    }

    /// The failure text, or for a passing clip that dropped frames, how many; nil for a clean pass.
    static func note(for row: SweepRow) -> String? {
        if let error = row.error { return error }
        switch row.actual?.droppedFrames ?? 0 {
        case ...0: return nil
        case 1: return "Dropped 1 frame."
        case let count: return "Dropped \(count) frames."
        }
    }
}
