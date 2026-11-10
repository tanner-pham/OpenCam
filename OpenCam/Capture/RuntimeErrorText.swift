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

    /// Said by the session when its own restart after a media-services reset left it stopped. Its domain is not
    /// AVFoundation's, so it is never taken for a reset.
    static func restartFailedMessage(applied: String?) -> String {
        let error = NSError(domain: "OpenCam.CameraSession", code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "The session did not start again after a media-services reset"])
        return message(for: error, applied: applied)
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
