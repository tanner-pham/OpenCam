import Foundation

/// What the current camera and its format can do with a point, read off the device by the session.
nonisolated struct FocusSupport: Sendable, Equatable {
    var focusPoint = false
    var exposurePoint = false
    var autoFocusOnce = false
    var continuousFocus = false
    var autoExposeOnce = false
    var continuousExposure = false
}
