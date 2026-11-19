import UIKit

/// A pinch that works beside a hold that has already begun, in place of cancelling it or waiting behind it (UIKit does neither
/// unless asked). A hold still waiting for its half second is not spared: the pinch fails it.
final class BesideHoldPinchRecognizer: UIPinchGestureRecognizer {
    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool {
        !Self.isBegunHold(preventedGestureRecognizer) && super.canPrevent(preventedGestureRecognizer)
    }

    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool {
        !Self.isBegunHold(preventingGestureRecognizer) && super.canBePrevented(by: preventingGestureRecognizer)
    }

    private static func isBegunHold(_ recognizer: UIGestureRecognizer) -> Bool {
        recognizer is UILongPressGestureRecognizer && (recognizer.state == .began || recognizer.state == .changed)
    }
}
