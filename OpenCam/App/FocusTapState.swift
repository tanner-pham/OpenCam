import CoreGraphics

/// What the viewfinder shows for taps and holds, and what each one asks of the camera. Pure: the model owns one and sends the request.
nonisolated struct FocusTapState: Sendable, Equatable {
    private(set) var marker: FocusMarker?
    /// What the lock holds; nil when not locked.
    private(set) var lock: FocusOutcome?
    private var lastSerial = 0

    var lockText: String? {
        switch lock {
        case .focusAndExposure?: "AE/AF lock"
        case .exposureOnly?: "AE lock"
        case .focusOnly?: "AF lock"
        case .nothing?, nil: nil
        }
    }

    /// Nil, and nothing shown, when the touch is not on the picture or both groups are set by hand.
    mutating func tapped(at viewPoint: CGPoint, geometry: PreviewGeometry, manual: ManualSettings) -> FocusRequest? {
        guard let point = geometry.devicePoint(forViewPoint: viewPoint), Self.outcome(allowedBy: manual) != .nothing else { return nil }
        show(at: viewPoint, isLocked: false)
        lock = nil
        return .point(point)
    }

    mutating func held(at viewPoint: CGPoint, geometry: PreviewGeometry, manual: ManualSettings) -> FocusRequest? {
        let outcome = Self.outcome(allowedBy: manual)
        guard let point = geometry.devicePoint(forViewPoint: viewPoint), outcome != .nothing else { return nil }
        show(at: viewPoint, isLocked: true)
        lock = outcome
        return .lock(point)
    }

    /// The camera answered a hold: the lock is what it could do, and `.nothing` clears it and the marker. Ignored when the marker
    /// it was for is gone or replaced, or is not a locked one.
    mutating func lockAnswered(_ outcome: FocusOutcome, serial: Int) {
        guard let marker, marker.serial == serial, marker.isLocked, lock != nil else { return }
        if outcome == .nothing {
            self.marker = nil
            lock = nil
        } else {
            lock = outcome
        }
    }

    /// A slider moved: a lock ends and the camera goes back to the centre.
    mutating func manualChanged() -> FocusRequest? {
        guard lock != nil else { return nil }
        lock = nil
        marker = nil
        return .recentre
    }

    /// The camera is changing; the session resets its own point.
    mutating func cameraChanged() {
        marker = nil
        lock = nil
    }

    mutating func markerFaded(serial: Int) {
        guard let marker, marker.serial == serial, !marker.isLocked else { return }
        self.marker = nil
    }

    private mutating func show(at viewPoint: CGPoint, isLocked: Bool) {
        lastSerial += 1
        marker = FocusMarker(viewPoint: viewPoint, serial: lastSerial, isLocked: isLocked)
    }

    private static func outcome(allowedBy manual: ManualSettings) -> FocusOutcome {
        switch (manual.focus == nil, manual.exposure == .automatic) {
        case (true, true): .focusAndExposure
        case (false, true): .exposureOnly
        case (true, false): .focusOnly
        case (false, false): .nothing
        }
    }
}
