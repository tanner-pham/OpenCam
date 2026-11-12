import AVKit
import SwiftUI

struct CameraRootView: View {
    @Bindable var model: CameraModel
    let library: LibraryStore?
    let launch: LaunchConfig
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var isLandscape: Bool { verticalSizeClass == .compact }

    /// Only the Simulator, which has the folded display alone, honours `-sliderPlacement picture`.
    private var isSliderForcedIntoPicture: Bool {
        #if targetEnvironment(simulator)
        launch.forcesPictureSlider
        #else
        false
        #endif
    }

    init(model: CameraModel, library: LibraryStore?, launch: LaunchConfig) {
        self.model = model
        self.library = library
        self.launch = launch
    }

    var body: some View {
        NavigationStack {
            CameraLayout(model: model, isLandscape: isLandscape)
                .modifier(CaptureFeedbackModifier(model: model))
                .background(Color.black.ignoresSafeArea())
                .persistentSystemOverlays(.hidden)
                .modifier(StripToolbarModifier(model: model, library: library, isLandscape: isLandscape))
                // The Camera Control takes the photo or starts and stops recording, through the same rules as the on-screen
                // button. Always enabled while this screen shows: a disabled interaction hands the button back to the system,
                // which opens Apple's Camera app. When capture is not allowed the model ignores the press.
                // Keep this inside the NavigationStack, on its content. Applied to the NavigationStack itself it left the strip's
                // items on the folded phone's outer display dead to taps (the open phone's floating bar still worked);
                // found by bisection on the folded Simulator, where moving only this line brought the taps back.
                .onCameraCaptureEvent { model.handleCaptureEvent(phase: $0.phase) }
        }
        .environment(\.isSliderForcedIntoPicture, isSliderForcedIntoPicture)
        // An import still running when the Library closed lands after the close read the last capture.
        .onChange(of: library?.importsFinished) { model.libraryImportFinished() }
        .fullScreenCover(isPresented: Binding(get: { model.isLibraryPresented && library != nil }, set: { model.isLibraryPresented = $0 }),
                         onDismiss: { Task { await model.closeLibrary() } }) {
            if let library { LibraryView(library: library, launch: launch) }
        }
        .sheet(item: $model.sheet) { sheet in
            switch sheet {
            case .record:
                RecordSettingsSheet(mode: model.mode,
                                    recordResolver: model.recordResolver,
                                    photoResolver: model.photoResolver,
                                    record: $model.record,
                                    photo: $model.photo,
                                    freeBytes: model.freeBytes,
                                    sweepCaption: model.sweepCaption,
                                    look: LookChoice(chips: model.lookChips, selectedID: model.lookChipID, reason: model.lookReason,
                                                     scrollsIntoView: model.scrollsToLookRow) { model.selectLook(chipID: $0) })
            case .sweep:
                SweepView(model: model)
            }
        }
    }
}
