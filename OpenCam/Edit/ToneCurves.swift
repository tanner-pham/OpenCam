import Foundation

/// The four curves of an edit: the RGB (master) curve and one per colour channel. Coding writes only the curves that are not identity.
nonisolated struct ToneCurves: Codable, Sendable, Hashable {
    var master = ToneCurve.identity, red = ToneCurve.identity, green = ToneCurve.identity, blue = ToneCurve.identity

    private enum CodingKeys: String, CodingKey { case master, red, green, blue }

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        master = try container.decodeIfPresent(ToneCurve.self, forKey: .master) ?? .identity
        red = try container.decodeIfPresent(ToneCurve.self, forKey: .red) ?? .identity
        green = try container.decodeIfPresent(ToneCurve.self, forKey: .green) ?? .identity
        blue = try container.decodeIfPresent(ToneCurve.self, forKey: .blue) ?? .identity
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if !master.isIdentity { try container.encode(master, forKey: .master) }
        if !red.isIdentity { try container.encode(red, forKey: .red) }
        if !green.isIdentity { try container.encode(green, forKey: .green) }
        if !blue.isIdentity { try container.encode(blue, forKey: .blue) }
    }

    subscript(channel: CurveChannel) -> ToneCurve {
        get {
            switch channel {
            case .master: master
            case .red: red
            case .green: green
            case .blue: blue
            }
        }
        set {
            switch channel {
            case .master: master = newValue
            case .red: red = newValue
            case .green: green = newValue
            case .blue: blue = newValue
            }
        }
    }

    var isIdentity: Bool { CurveChannel.allCases.allSatisfy { self[$0].isIdentity } }
}
