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
        do {
            let capabilities = try CaptureCapabilities.bundledFixture()
            #if targetEnvironment(simulator)
            let isSimulator = true
            let session: CameraSession? = nil
            #else
            let isSimulator = false
            let session: CameraSession? = CameraSession()
            #endif
            _model = State(initialValue: CameraModel(config: config, capabilities: capabilities, isSimulator: isSimulator))
            _session = State(initialValue: session)
        } catch {
            Self.logger.error("Fixture failed to load: \(String(describing: error), privacy: .public)")
            _model = State(initialValue: nil)
        }
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
