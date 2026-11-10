import SwiftUI

nonisolated enum Theme {
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
    }

    enum Size {
        static let minTarget: CGFloat = 44
        static let topBar: CGFloat = 56
        static let captureButton: CGFloat = 40
        static let histogramWidth: CGFloat = 64
        static let histogramHeight: CGFloat = 32
        static let meterWidth: CGFloat = 72
        static let cornerInset: CGFloat = 24
        static let sectionHeaderInset: CGFloat = 20
        static let formatLabel: CGFloat = 28
        static let chipLabelHeight: CGFloat = 35
        static let noticeLine: CGFloat = 18
        static let lookChipMax: CGFloat = 160
    }

    enum Text {
        static let caption = Font.system(size: 10, weight: .semibold)
        static let compactCaption = Font.system(size: 9, weight: .semibold)
        static let compactValue = Font.system(size: 13, weight: .semibold).monospacedDigit()
        static let value = Font.system(size: 17, weight: .semibold).monospacedDigit()
    }

    static let accent = Color(red: 1.0, green: 0.8, blue: 0.2)
    static let recordRed = Color(red: 1.0, green: 0.23, blue: 0.19)
}
