import Foundation

nonisolated struct CaptureCapabilities: Codable, Sendable, Equatable {
    var lenses: [Lens]
    var videoOptions: [VideoOption]
    var photoOptions: [PhotoOption]
    var osBuild: String
    var modelIdentifier: String

    static let fixtureName = "CapabilitiesFixture"

    static func bundledFixture(in bundle: Bundle = .main) throws(CapabilityError) -> CaptureCapabilities {
        guard let url = bundle.url(forResource: fixtureName, withExtension: "json") else {
            throw .fixtureMissing
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw .unreadable(path: url.path, reason: String(describing: error))
        }
        return try decode(data)
    }

    static func decode(_ data: Data) throws(CapabilityError) -> CaptureCapabilities {
        do {
            return try JSONDecoder().decode(CaptureCapabilities.self, from: data)
        } catch {
            throw .unreadable(path: "(data)", reason: String(describing: error))
        }
    }

    func encoded() throws(CapabilityError) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            return try encoder.encode(self)
        } catch {
            throw .unwritable(path: "(data)", reason: String(describing: error))
        }
    }

    func videoOptions(forLens id: String) -> [VideoOption] {
        videoOptions.filter { $0.lensID == id }
    }

    func photoOptions(forLens id: String) -> [PhotoOption] {
        photoOptions.filter { $0.lensID == id }
    }
}
