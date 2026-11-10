import Foundation

/// Checks `condition` every 10 ms until it holds or about two seconds pass; returns whether it held.
@MainActor func eventually(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<200 {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}
