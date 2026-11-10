import OSLog
import SwiftUI
import UIKit

@main
struct OpenCamApp: App {
    private static let logger = Logger(subsystem: "local.opencam.app", category: "App")

    private let config: LaunchConfig
    @State private var model: CameraModel?
    /// Nil when a store could not be made; the camera then shows no Library.
    @State private var library: LibraryStore?
    /// Nil in the Simulator, which has no camera.
    @State private var session: CameraSession?

    init() {
        let config = LaunchConfig.parse(ProcessInfo.processInfo.arguments)
        self.config = config
        // One capture store serves the camera and the Library, so photos, recordings, sweeps and imports share one numbering.
        let captureStore = Self.makeCaptureStore()
        // One look store serves the camera, the Library and the editor. It is made, and seeded, before the camera model so a
        // -cameraLook launch finds its look.
        let looks = Self.makeLookStore(config: config)
        let library = captureStore.flatMap { captures in looks.flatMap { Self.makeLibrary(captures: captures, looks: $0, config: config) } }
        _library = State(initialValue: library)
        #if targetEnvironment(simulator)
        // The fixture stands in for the scan in the Simulator only.
        do {
            let capabilities = try CaptureCapabilities.bundledFixture()
            _model = State(initialValue: CameraModel(config: config, capabilities: capabilities, isSimulator: true, captureStore: captureStore,
                                                     isLibraryAvailable: library != nil, lookStore: looks))
        } catch {
            Self.logger.error("[OpenCamApp:init] Fixture failed to load — {error: \(String(describing: error), privacy: .public)}")
            _model = State(initialValue: nil)
        }
        _session = State(initialValue: nil)
        #else
        // On the device nothing is known until the scan or the cache provides it.
        let empty = CaptureCapabilities(lenses: [], videoOptions: [], photoOptions: [], osBuild: "", modelIdentifier: "")
        _model = State(initialValue: CameraModel(config: config, capabilities: empty, isSimulator: false, captureStore: captureStore,
                                                 isLibraryAvailable: library != nil, lookStore: looks))
        _session = State(initialValue: CameraSession())
        #endif
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let model {
                    CameraRootView(model: model, library: library, launch: config)
                } else {
                    Color.black
                        .ignoresSafeArea()
                        .overlay { Text("Camera formats could not be loaded.").foregroundStyle(.white) }
                }
            }
            .preferredColorScheme(.dark)
            .environment(\.previewSource, session?.previewSource)
            .task { forceOrientation() }
            .task { await LookRenderer.warmUp() }
            .task {
                guard let model, let session else { return }
                // Diagnostic launch: the check needs the cameras to itself, so the camera is not started.
                if ProcessInfo.processInfo.arguments.contains("-rawCheck") {
                    await RawCheck.runAndWrite()
                    return
                }
                await model.start(session: session)
            }
        }
    }

    private static func makeCaptureStore() -> CaptureStore? {
        do throws(CaptureStoreError) {
            return try CaptureStore.appDefault()
        } catch {
            logger.error("\(error.description, privacy: .public)")
            return nil
        }
    }

    /// Nil when the store could not be made: the Library is then unavailable and the camera has only None.
    private static func makeLookStore(config: LaunchConfig) -> LookStore? {
        do throws(LookStoreError) {
            let looks = try LookStore.appDefault()
            #if targetEnvironment(simulator)
            if config.seedsLook {
                do throws(LookStoreError) {
                    _ = try LookSeeder.seedWarmFade(into: looks)
                } catch {
                    logger.error("\(error.description, privacy: .public)")
                }
            }
            #endif
            return looks
        } catch {
            logger.error("\(error.description, privacy: .public)")
            return nil
        }
    }

    private static func makeLibrary(captures: CaptureStore, looks: LookStore, config: LaunchConfig) -> LibraryStore? {
        #if targetEnvironment(simulator)
        if config.seedsSamples {
            do throws(LibraryError) {
                _ = try SampleSeeder.seedIfEmpty(captures)
            } catch {
                logger.error("\(error.description, privacy: .public)")
            }
        }
        #endif
        let library = LibraryStore(captures: captures, edits: EditStore(directory: captures.directory),
                                   looks: looks, thumbnails: ThumbnailCache.appDefault())
        library.reload()
        return library
    }

    private func forceOrientation() {
        guard let orientation = config.orientation else { return }
        let mask: UIInterfaceOrientationMask = orientation == .landscape ? .landscapeRight : .portrait
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
        }
    }
}
