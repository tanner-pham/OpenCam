import SwiftUI
import UIKit

/// Two fingers pinching in the viewfinder. At the start the layer keeps the model's pinch, and each change zooms from it, so a
/// second pinch continues where the first stopped. Never touches focus and does not end a lock.
///
/// How it sits with the other two recognizers on the layer (the tap and the one-finger hold, which acts when it begins):
/// the tap needs one touch, so two fingers fail it. A hold that has not begun (under half a second) is failed by the pinch, so
/// two fingers arriving early leave no marker and no lock. A hold that has begun is not failed by a second finger, so the pinch
/// recognizes beside it: the lock stays and the pinch zooms. That is `BesideHoldPinchRecognizer`'s `canPrevent` and
/// `canBePrevented(by:)`, which UIKit asks for each pair, so no delegate (SwiftUI owns it) is needed.
struct ZoomPinchRecognizer: UIGestureRecognizerRepresentable {
    let model: CameraModel

    /// The model's pinch when the fingers went down.
    final class Coordinator {
        var start = 1.0
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> BesideHoldPinchRecognizer {
        BesideHoldPinchRecognizer()
    }

    func handleUIGestureRecognizerAction(_ recognizer: BesideHoldPinchRecognizer, context: Context) {
        switch recognizer.state {
        case .began:
            context.coordinator.start = model.pinch
        case .changed:
            model.setPinch(magnification: recognizer.scale, from: context.coordinator.start)
        default:
            break
        }
    }
}
