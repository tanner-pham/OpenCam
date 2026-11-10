import SwiftUI
import UIKit

@main
struct DuoCamPrototypeApp: App {
    private let config = LaunchConfig.parse()

    var body: some Scene {
        WindowGroup {
            CameraRootView(config: config)
                .preferredColorScheme(.dark)
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
