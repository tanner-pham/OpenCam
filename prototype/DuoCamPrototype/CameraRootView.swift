import SwiftUI

struct CameraRootView: View {
    @State private var model: CaptureModel
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    init(config: LaunchConfig) {
        _model = State(initialValue: CaptureModel(config: config))
    }

    private var isLandscape: Bool { verticalSizeClass == .compact }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                Group {
                    if isLandscape {
                        FoldedHorizontalView(model: model, size: geo.size)
                    } else if model.mode == .video {
                        FoldedVerticalVideoView(model: model, size: geo.size)
                    } else {
                        FoldedVerticalView(model: model, size: geo.size)
                    }
                }
            }
            .ignoresSafeArea(.container, edges: [.top, .bottom])
            .background(Color.black.ignoresSafeArea())
            .persistentSystemOverlays(.hidden)
            .toolbar { StripToolbar(model: model, isLandscape: isLandscape) }
        }
        .sheet(item: $model.sheet) { sheet in
            switch sheet {
            case .record: RecordSettingsSheet(model: model)
            case .monitor: MonitorSheet(model: model)
            case .audio: AudioSheet(model: model)
            }
        }
    }
}
