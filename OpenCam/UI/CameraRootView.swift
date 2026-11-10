import AVKit
import SwiftUI

struct CameraRootView: View {
    @Bindable var model: CameraModel
    @Environment(\.verticalSizeClass) private var verticalSizeClass

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
        // The Camera Control takes the photo or starts and stops recording, through the same rules as the on-screen button.
        // Always enabled while this screen shows: a disabled interaction hands the button back to the system, which opens
        // Apple's Camera app. When capture is not allowed the model ignores the press.
        .onCameraCaptureEvent { model.handleCaptureEvent(phase: $0.phase) }
        .sheet(item: $model.sheet) { sheet in
            switch sheet {
            case .record:
                RecordSettingsSheet(mode: model.mode,
                                    recordResolver: model.recordResolver,
                                    photoResolver: model.photoResolver,
                                    record: $model.record,
                                    photo: $model.photo,
                                    freeBytes: model.freeBytes,
                                    sweepCaption: model.sweepCaption)
            case .sweep:
                SweepView(model: model)
            }
        }
    }
}
