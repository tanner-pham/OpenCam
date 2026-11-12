import OSLog
import UIKit

/// `UIApplication`'s background task (UIApplication.h: `beginBackgroundTaskWithName:expirationHandler:`, `endBackgroundTask:`).
/// The system may refuse a task (it returns `.invalid`), and it ends the time when the handler runs; the handler must end the
/// task, so it does. Either way `end()` calls `endBackgroundTask` at most once, and never for a task that was not begun.
final class SystemBackgroundWork: BackgroundWork {
    private static let logger = Logger(subsystem: "local.opencam.app", category: "SystemBackgroundWork")
    private var identifier = UIBackgroundTaskIdentifier.invalid

    init(name: String) {
        identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            Self.logger.error("[SystemBackgroundWork:expired] The background time ran out — {name: \(name, privacy: .public)}")
            self?.end()
        }
        if identifier == .invalid {
            Self.logger.error("[SystemBackgroundWork:init] The system gave no background time — {name: \(name, privacy: .public)}")
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        let finished = identifier
        identifier = .invalid
        UIApplication.shared.endBackgroundTask(finished)
    }
}
