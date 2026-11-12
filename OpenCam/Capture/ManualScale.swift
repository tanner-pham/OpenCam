import Foundation

/// The values a manual control steps through, bottom of the slider first.
nonisolated struct ManualScale: Sendable, Equatable {
    /// Ascending, never empty; step 0 is the bottom of the slider.
    let values: [Double]
    /// A haptic each time the thumb crosses a multiple of this.
    let detentStride: Int
    /// Steps per VoiceOver increment.
    let adjustStride: Int
    /// Shutter and ISO: nearest by stops.
    let isLogarithmic: Bool

    static func make(for control: ManualControl, ranges: ManualRanges) -> ManualScale? {
        switch control {
        case .shutter:
            guard let range = ranges.shutterSeconds else { return nil }
            return scale(shutterValues(in: range, frameSeconds: ranges.frameSeconds), detent: 1, adjust: 1, log: true)
        case .iso:
            guard let range = ranges.iso else { return nil }
            return scale(isoValues(in: Double(range.lowerBound)...Double(range.upperBound)), detent: 1, adjust: 1, log: true)
        case .bias:
            // Converting an infinite bound to an Int traps.
            guard let range = ranges.bias, range.lowerBound.isFinite, range.upperBound.isFinite else { return nil }
            // No camera's bias runs past a few stops; a wild finite bound would overflow the Int conversion too.
            let lower = max(Double(range.lowerBound), -Self.biasLimit)
            let upper = min(Double(range.upperBound), Self.biasLimit)
            let low = Int((lower * 3 - 1e-6).rounded(.up))
            let high = Int((upper * 3 + 1e-6).rounded(.down))
            guard low <= high else { return nil }
            return scale((low...high).map { Double($0) / 3 }, detent: 1, adjust: 1, log: false)
        case .temperature:
            guard ranges.hasWhiteBalance else { return nil }
            return scale((25...100).map { Double($0 * 100) }, detent: 1, adjust: 1, log: false)
        case .tint:
            guard ranges.hasWhiteBalance else { return nil }
            return scale((-50...50).map { Double($0) }, detent: 10, adjust: 5, log: false)
        case .focus:
            guard ranges.hasFocus else { return nil }
            return scale((0...100).map { Double($0) / 100 }, detent: 25, adjust: 5, log: false)
        }
    }

    func step(nearest value: Double) -> Int {
        guard value.isFinite else { return 0 }
        let useLog = isLogarithmic && value > 0
        var best = 0
        var bestDistance = Double.infinity
        for (index, candidate) in values.enumerated() {
            let distance = useLog ? abs(log(candidate / value)) : abs(candidate - value)
            if distance < bestDistance {
                best = index
                bestDistance = distance
            }
        }
        return best
    }

    /// Clamped to the scale.
    func step(_ step: Int, movedBy steps: Int) -> Int {
        min(max(step + steps, 0), values.count - 1)
    }

    func crossesDetent(from: Int, to: Int) -> Bool {
        guard from != to else { return false }
        guard detentStride > 1 else { return true }
        return Self.floorDivide(from, detentStride) != Self.floorDivide(to, detentStride)
    }

    private static func floorDivide(_ a: Int, _ b: Int) -> Int {
        let quotient = a / b
        return (a % b != 0 && a < 0) ? quotient - 1 : quotient
    }

    private static func scale(_ values: [Double], detent: Int, adjust: Int, log: Bool) -> ManualScale? {
        guard !values.isEmpty else { return nil }
        return ManualScale(values: values, detentStride: detent, adjustStride: adjust, isLogarithmic: log)
    }

    /// The widest exposure bias, in stops, a scale is ever built for.
    private static let biasLimit = 24.0

    private static let shutterDenominators: [Double] = [
        8000, 6400, 5000, 4000, 3200, 2500, 2000, 1600, 1250, 1000, 800, 640, 500, 400, 320, 250, 200, 160,
        125, 100, 80, 60, 50, 40, 30, 25, 20, 15, 13, 10, 8, 6, 5, 4, 3, 2.5, 2, 1.6, 1.3, 1,
    ]

    private static func shutterValues(in range: ClosedRange<Double>, frameSeconds: Double?) -> [Double] {
        var values = shutterDenominators.map { 1 / $0 }.filter { range.contains($0) }
        if let frame = frameSeconds, frame.isFinite, frame > 0 {
            let added = [frame, frame / 2].filter { range.contains($0) }
            values.removeAll { value in added.contains { abs(value - $0) <= $0 * 0.02 } }
            values += added
        }
        return Set(values).sorted()
    }

    private static func isoValues(in range: ClosedRange<Double>) -> [Double] {
        let below: [Double] = [25, 32, 40, 50, 64, 80]
        let decade: [Double] = [100, 125, 160, 200, 250, 320, 400, 500, 640, 800]
        let table = below + [1.0, 10, 100].flatMap { scale in decade.map { $0 * scale } }
        let ends = [range.lowerBound, range.upperBound]
        let inside = table.filter { value in
            range.contains(value) && !ends.contains { value != $0 && abs(value - $0) <= $0 * 0.02 }
        }
        return Set(inside + ends).sorted()
    }
}
