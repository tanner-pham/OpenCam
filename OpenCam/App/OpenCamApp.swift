import OSLog
import SwiftUI
import UIKit

@main
struct OpenCamApp: App {
    private static let logger = Logger(subsystem: "local.opencam.app", category: "App")

    private let config: LaunchConfig
    @State private var model: CameraModel?
    /// Nil in the Simulator, which has no camera.
    @State private var session: CameraSession?

    init() {
        let config = LaunchConfig.parse(ProcessInfo.processInfo.arguments)
        self.config = config
        #if targetEnvironment(simulator)
        // The fixture stands in for the scan in the Simulator only.
        do {
            let capabilities = try CaptureCapabilities.bundledFixture()
            _model = State(initialValue: CameraModel(config: config, capabilities: capabilities, isSimulator: true))
        } catch {
            Self.logger.error("Fixture failed to load: \(String(describing: error), privacy: .public)")
            _model = State(initialValue: nil)
        }
        _session = State(initialValue: nil)
        #else
        // On the device nothing is known until the scan or the cache provides it.
        let empty = CaptureCapabilities(lenses: [], videoOptions: [], photoOptions: [], osBuild: "", modelIdentifier: "")
        _model = State(initialValue: CameraModel(config: config, capabilities: empty, isSimulator: false))
        _session = State(initialValue: CameraSession())
        #endif
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let model {
                    CameraRootView(model: model)
                } else {
                    Color.black
                        .ignoresSafeArea()
                        .overlay { Text("Camera formats could not be loaded.").foregroundStyle(.white) }
                }
            }
            .preferredColorScheme(.dark)
            .environment(\.previewSource, session?.previewSource)
            .task { forceOrientation() }
            .task {
                guard let model, let session else { return }
                await model.start(session: session)
            }
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
