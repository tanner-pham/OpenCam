import CoreGraphics
import Foundation

/// Tap to focus and expose, hold to lock. The decisions are `FocusTapState`'s and `FocusPlan`'s; this turns a touch into a point
/// and sends the request to the session. A touch never configures the session, raises `isViewfinderChanging` or changes `manual`.
extension CameraModel {
    /// A camera to aim: not while the sweep, a scan, the Library or a configure holds the picture. Recording is allowed.
    var canAim: Bool {
        hasCamera && !isSweeping && !isScanningFormats && !isLibraryPresented && !isViewfinderChanging
    }

    func focusTapped(at viewPoint: CGPoint, in size: CGSize) {
        guard canAim, let geometry = aimGeometry(in: size),
              let request = focusTap.tapped(at: viewPoint, geometry: geometry, manual: manual) else { return }
        send(request, from: viewPoint)
    }

    func focusHeld(at viewPoint: CGPoint, in size: CGSize) {
        guard canAim, let geometry = aimGeometry(in: size),
              let request = focusTap.held(at: viewPoint, geometry: geometry, manual: manual) else { return }
        send(request, from: viewPoint)
    }

    func focusMarkerFaded(serial: Int) {
        focusTap.markerFaded(serial: serial)
    }

    /// A slider or Auto changed what is set by hand: a lock ends and the camera goes back to the centre.
    func manualChangedForFocus() {
        guard let request = focusTap.manualChanged() else { return }
        sendFocus(request)
    }

    /// `-focusLock on`: holds at the centre of the picture each time the layer settles on a size (a launch may rotate after the first layout).
    func holdFocusOnLaunchIfAsked(in size: CGSize) {
        guard holdsFocusOnLaunch, canAim, size.width > 0, size.height > 0 else { return }
        focusHeld(at: CGPoint(x: size.width / 2, y: size.height / 2), in: size)
    }

    // MARK: Sending

    /// The Simulator's picture is the view; the device's comes from the preview layer.
    private func aimGeometry(in size: CGSize) -> PreviewGeometry? {
        isSimulator ? .filling(size) : focusGeometry(size)
    }

    private func send(_ request: FocusRequest, from viewPoint: CGPoint) {
        if !isSimulator {
            switch request {
            case .point(let point), .lock(let point): PreviewUIView.journalConverterDisagreement(viewPoint: viewPoint, computed: point)
            case .recentre: break
            }
        }
        sendFocus(request)
    }

    /// Starts a request when none runs; a running one leaves this one waiting in place of any earlier one. Without a session
    /// (the Simulator) only the state changes.
    private func sendFocus(_ request: FocusRequest) {
        guard let configurator, let job = focusRequests.request(request) else { return }
        Task { await runFocusRequests(from: job.value, on: configurator) }
    }

    /// Sends the request, then the latest one that waited meanwhile, until none waits.
    private func runFocusRequests(from first: FocusRequest, on configurator: any SessionConfigurator) async {
        var request: FocusRequest? = first
        while let current = request {
            _ = await configurator.applyFocus(current)
            request = focusRequests.finish()?.value
        }
    }
}
