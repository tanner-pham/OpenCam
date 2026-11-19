import SwiftUI
import UIKit

/// One finger held for half a second in the viewfinder; acts when the hold begins.
struct FocusHoldRecognizer: UIGestureRecognizerRepresentable {
    let onHold: (CGPoint) -> Void

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = 0.5
        recognizer.numberOfTouchesRequired = 1
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        guard recognizer.state == .began else { return }
        onHold(context.converter.localLocation)
    }
}
