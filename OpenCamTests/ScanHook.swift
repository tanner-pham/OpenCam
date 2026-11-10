import Foundation

/// Lets a test act on the model from inside a fake scan, while the model is scanning.
@MainActor final class ScanHook {
    var action: (() async -> Void)?

    func run() async {
        await action?()
    }
}
