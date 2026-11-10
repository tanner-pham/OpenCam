import SwiftUI
import UIKit

@main
struct OpenCamApp: App {
    private static let lensID = "wide"
    private static let freeBytes: Int64 = 141_000_000_000

    private let config = LaunchConfig.parse(ProcessInfo.processInfo.arguments)
    private let recordResolver: RecordSelectionResolver
    private let photoResolver: PhotoSelectionResolver
    private let loadError: String?
    @State private var record: RecordSelection
    @State private var photo: PhotoSelection
    @State private var isRecordSheetShown: Bool

    init() {
        let config = LaunchConfig.parse(ProcessInfo.processInfo.arguments)
        let placeholderRecord = RecordSelection(family: .hevc, quality: "High", resolution: .named(width: 3840, height: 2160), frameRate: 30, colour: .rec709)
        let placeholderPhoto = PhotoSelection(format: .heif, megapixels: 12)
        do {
            let capabilities = try CaptureCapabilities.bundledFixture()
            let lens = capabilities.lenses.first { $0.id == Self.lensID }
            let recordResolver = RecordSelectionResolver(options: capabilities.videoOptions, lens: lens)
            let photoResolver = PhotoSelectionResolver(options: capabilities.photoOptions, lenses: capabilities.lenses, lensID: Self.lensID)
            self.recordResolver = recordResolver
            self.photoResolver = photoResolver
            self.loadError = nil
            _record = State(initialValue: recordResolver.defaultSelection() ?? placeholderRecord)
            _photo = State(initialValue: photoResolver.defaultSelection() ?? placeholderPhoto)
        } catch {
            self.recordResolver = RecordSelectionResolver(options: [], lens: nil)
            self.photoResolver = PhotoSelectionResolver(options: [], lenses: [], lensID: Self.lensID)
            self.loadError = String(describing: error)
            _record = State(initialValue: placeholderRecord)
            _photo = State(initialValue: placeholderPhoto)
        }
        _isRecordSheetShown = State(initialValue: config.screen == .record)
    }

    var body: some Scene {
        WindowGroup {
            Color.black
                .ignoresSafeArea()
                .overlay { if let loadError { Text(loadError).foregroundStyle(.white) } }
                .preferredColorScheme(.dark)
                .sheet(isPresented: $isRecordSheetShown) {
                    RecordSettingsSheet(mode: config.mode,
                                        recordResolver: recordResolver,
                                        photoResolver: photoResolver,
                                        record: $record,
                                        photo: $photo,
                                        freeBytes: Self.freeBytes)
                }
                .task { forceOrientation() }
        }
    }

    private func forceOrientation() {
        guard let orientation = config.orientation else { return }
        let mask: UIInterfaceOrientationMask = orientation == .landscape ? .landscapeRight : .portrait
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
        }
    }
}
