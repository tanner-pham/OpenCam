import AVFoundation

/// The text of `SessionEvent.runtimeError`, written by `CameraSession` and read by `CameraModel`, which tells a media-services
/// reset apart by it. Pure, so both sides and the tests share one format.
nonisolated enum RuntimeErrorText {
    /// The error's domain, code and description, its underlying error (`NSUnderlyingErrorKey`) as domain and code, and
    /// `applied` (the lens and mode of the applied configuration). Only the top-level error is written as
    /// `domain: <d>, code: <n>`; the underlying one never matches `isMediaServicesReset`.
    static func message(for error: NSError?, applied: String?) -> String {
        var parts = [error.map { "domain: \($0.domain), code: \($0.code), \($0.localizedDescription)" } ?? "no error"]
        if let underlying = error?.userInfo[NSUnderlyingErrorKey] as? NSError {
            parts.append("underlying: \(underlying.domain) \(underlying.code)")
        }
        parts.append(applied ?? "lens: none, mode: none")
        return "[CameraSession:runtimeError] Session stopped — {\(parts.joined(separator: ", "))}"
    }

    /// AVError.h: AVErrorMediaServicesWereReset (-11819) in AVFoundationErrorDomain. A message that names a domain must name
    /// that one with the code; one without a domain (written before the domain was included) is matched on the code alone.
    static func isMediaServicesReset(_ message: String) -> Bool {
        let code = "code: \(AVError.Code.mediaServicesWereReset.rawValue)"
        guard message.contains(code + ",") || message.contains(code + "}") else { return false }
        guard message.contains("domain: ") else { return true }
        return message.contains("domain: \(AVFoundationErrorDomain), \(code)")
    }
}
