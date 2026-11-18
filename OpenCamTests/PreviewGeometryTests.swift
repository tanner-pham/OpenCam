import CoreGraphics
import Testing
@testable import OpenCam

@Suite struct PreviewGeometryTests {
    static let pairs: [(rotation: Double, isMirrored: Bool)] = [0, 90, 180, 270].flatMap { [($0, false), ($0, true)] }
    let view = CGSize(width: 400, height: 400)
    let sensor = CGSize(width: 400, height: 400)

    func geometry(_ rotation: Double, mirrored: Bool = false) -> PreviewGeometry {
        PreviewGeometry(viewSize: view, sensorSize: sensor, rotation: rotation, isMirrored: mirrored)
    }

    @Test func everyAngleAndMirrorSendsTheCornersToTheSensorsCorners() throws {
        let expected: [(Double, Bool, FocusPoint)] = [
            (0, false, FocusPoint(x: 0, y: 0)), (90, false, FocusPoint(x: 0, y: 1)),
            (180, false, FocusPoint(x: 1, y: 1)), (270, false, FocusPoint(x: 1, y: 0)),
            (90, true, FocusPoint(x: 0, y: 0)), (270, true, FocusPoint(x: 1, y: 1)),
        ]
        for (rotation, isMirrored, point) in expected {
            let result = try #require(geometry(rotation, mirrored: isMirrored).devicePoint(forViewPoint: .zero))
            #expect(abs(result.x - point.x) < 1e-9 && abs(result.y - point.y) < 1e-9, "rotation \(rotation) mirrored \(isMirrored): \(result)")
        }
    }

    @Test func theCentreIsTheCentreEverywhere() throws {
        for pair in Self.pairs {
            let result = try #require(geometry(pair.rotation, mirrored: pair.isMirrored).devicePoint(forViewPoint: CGPoint(x: 200, y: 200)))
            #expect(abs(result.x - 0.5) < 1e-9 && abs(result.y - 0.5) < 1e-9)
        }
    }

    @Test func aTapInTheBarsIsNotAPoint() {
        let wide = CGSize(width: 1600, height: 900)
        let fourThree = PreviewGeometry(viewSize: wide, sensorSize: CGSize(width: 4032, height: 3024), rotation: 0, isMirrored: false)
        #expect(fourThree.devicePoint(forViewPoint: CGPoint(x: 100, y: 450)) == nil)
        #expect(fourThree.devicePoint(forViewPoint: CGPoint(x: 800, y: 450)) != nil)
        for pair in Self.pairs {
            let geometry = PreviewGeometry(viewSize: wide, sensorSize: CGSize(width: 4032, height: 3024), rotation: pair.rotation, isMirrored: pair.isMirrored)
            for column in 0..<20 {
                for row in 0..<20 {
                    let point = CGPoint(x: Double(column) * 80 + 40, y: Double(row) * 45 + 22)
                    guard let result = geometry.devicePoint(forViewPoint: point) else { continue }
                    #expect((0...1).contains(result.x) && (0...1).contains(result.y), "\(pair) \(point) gave \(result)")
                }
            }
        }
    }

    @Test func thePictureIsFittedTurned() throws {
        let geometry = PreviewGeometry(viewSize: CGSize(width: 390, height: 844), sensorSize: CGSize(width: 4032, height: 3024), rotation: 90, isMirrored: false)
        // The shown picture is 3024 x 4032 turned, so 390 x 520, centred: its rows run from 162 to 682.
        #expect(geometry.devicePoint(forViewPoint: CGPoint(x: 100, y: 160)) == nil)
        #expect(geometry.devicePoint(forViewPoint: CGPoint(x: 100, y: 684)) == nil)
        #expect(geometry.devicePoint(forViewPoint: CGPoint(x: 0, y: 162.5)) != nil)
        #expect(geometry.devicePoint(forViewPoint: CGPoint(x: 389.9, y: 681.5)) != nil)
        let corner = try #require(geometry.devicePoint(forViewPoint: CGPoint(x: 0, y: 162)))
        #expect(abs(corner.x) < 1e-9 && abs(corner.y - 1) < 1e-9)
    }

    @Test func viewPointRoundTrips() throws {
        let sensor = CGSize(width: 4032, height: 3024)
        for pair in Self.pairs {
            let geometry = PreviewGeometry(viewSize: CGSize(width: 390, height: 844), sensorSize: sensor, rotation: pair.rotation, isMirrored: pair.isMirrored)
            for point in [FocusPoint(x: 0.2, y: 0.7), FocusPoint(x: 0.9, y: 0.1), .centre] {
                let back = try #require(geometry.devicePoint(forViewPoint: geometry.viewPoint(for: point)))
                #expect(abs(back.x - point.x) < 1e-9 && abs(back.y - point.y) < 1e-9, "\(pair) \(point) came back \(back)")
            }
        }
    }

    @Test func nearlyAQuarterTurnIsOne() throws {
        let nearly = try #require(geometry(89.6).devicePoint(forViewPoint: .zero))
        let exact = try #require(geometry(90).devicePoint(forViewPoint: .zero))
        #expect(nearly == exact)
        let nan = try #require(geometry(.nan).devicePoint(forViewPoint: .zero))
        #expect(nan == FocusPoint(x: 0, y: 0))
        let negative = try #require(geometry(-90).devicePoint(forViewPoint: .zero))
        let threeQuarters = try #require(geometry(270).devicePoint(forViewPoint: .zero))
        #expect(negative == threeQuarters)
    }

    @Test func anEmptyViewHasNoPoints() {
        let empty = PreviewGeometry(viewSize: .zero, sensorSize: sensor, rotation: 0, isMirrored: false)
        #expect(empty.devicePoint(forViewPoint: .zero) == nil)
        let noSensor = PreviewGeometry(viewSize: view, sensorSize: .zero, rotation: 0, isMirrored: false)
        #expect(noSensor.devicePoint(forViewPoint: CGPoint(x: 10, y: 10)) == nil)
        #expect(PreviewGeometry.filling(view).devicePoint(forViewPoint: CGPoint(x: 100, y: 300)) == FocusPoint(x: 0.25, y: 0.75))
    }
}
