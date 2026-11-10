import Foundation
import Observation

@Observable
final class CameraModel {
    private static let simulatorFreeBytes: Int64 = 141_000_000_000
    private static let placeholderRecord = RecordSelection(family: .hevc, quality: "High", resolution: .named(width: 3840, height: 2160), frameRate: 30, colour: .rec709)
    private static let placeholderPhoto = PhotoSelection(format: .heif, megapixels: 12)

    var mode: CaptureMode { didSet { persist() } }
    var record: RecordSelection { didSet { persist() } }
    var photo: PhotoSelection { didSet { persist() } }
    var sheet: CameraSheet?
    var phase: CameraPhase
    var freeBytes: Int64
    var notice: String?
    var meterLevels: [Double] = [0.62, 0.54]
    var lastCapture: URL?
    private(set) var capabilities: CaptureCapabilities
    private(set) var lensID: String { didSet { persist() } }
    private(set) var isRecording: Bool
    private(set) var recordingStart: Date?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let isScripted: Bool

    init(config: LaunchConfig, capabilities: CaptureCapabilities, isSimulator: Bool, defaults: UserDefaults = .standard) {
        self.capabilities = capabilities
        self.defaults = defaults
        self.isScripted = config.isScripted
        self.phase = isSimulator ? .simulator : .scanning
        self.freeBytes = Self.simulatorFreeBytes
        self.isRecording = config.isRecording
        self.recordingStart = config.isRecording ? Date().addingTimeInterval(-42) : nil
        switch config.screen {
        case .main: self.sheet = nil
        case .record: self.sheet = .record
        case .sweep: self.sheet = .sweep
        }

        let saved = config.isScripted ? nil : SavedSelections.load(from: defaults)
        let defaultID = Self.defaultLens(in: capabilities)?.id ?? ""
        let lensID = saved.map { saved in capabilities.lenses.contains { $0.id == saved.lensID } ? saved.lensID : defaultID } ?? defaultID
        self.lensID = lensID
        self.mode = saved?.mode ?? config.mode

        let lens = capabilities.lenses.first { $0.id == lensID }
        let recordResolver = RecordSelectionResolver(options: capabilities.videoOptions, lens: lens)
        let photoResolver = PhotoSelectionResolver(options: capabilities.photoOptions, lenses: capabilities.lenses, lensID: lensID)
        self.record = Self.settle(saved?.record, with: recordResolver) ?? Self.placeholderRecord
        self.photo = Self.settle(saved?.photo, with: photoResolver) ?? Self.placeholderPhoto
    }

    var lenses: [Lens] { capabilities.lenses }
    var currentLens: Lens? { capabilities.lenses.first { $0.id == lensID } }

    var recordResolver: RecordSelectionResolver {
        RecordSelectionResolver(options: capabilities.videoOptions, lens: currentLens)
    }

    var photoResolver: PhotoSelectionResolver {
        PhotoSelectionResolver(options: capabilities.photoOptions, lenses: capabilities.lenses, lensID: lensID)
    }

    var currentVideoOption: VideoOption? { recordResolver.option(for: record) }
    var currentPhotoOption: PhotoOption? { photoResolver.option(for: photo) }

    var summaryParts: [String] {
        switch mode {
        case .video: [record.family.title, record.resolution.label, record.colour.shortName]
        case .photo: [photo.format.rawValue, "\(photo.megapixels) MP"]
        }
    }

    var remainingText: String {
        guard let option = currentVideoOption else { return "-- min" }
        return "\(DataRateEstimator.minutesRemaining(freeBytes: freeBytes, option: option)) min"
    }

    /// Audio meters and the remaining-time estimate describe video recording, so photo mode hides them.
    var showsVideoReadouts: Bool { mode == .video }

    var canCapture: Bool {
        guard phase == .ready else { return false }
        switch mode {
        case .video: return currentVideoOption != nil
        case .photo: return currentPhotoOption != nil
        }
    }

    func selectLens(_ id: String) {
        guard id != lensID, capabilities.lenses.contains(where: { $0.id == id }) else { return }
        lensID = id
        settleSelections()
    }

    func replaceCapabilities(_ capabilities: CaptureCapabilities) {
        self.capabilities = capabilities
        if !capabilities.lenses.contains(where: { $0.id == lensID }) {
            lensID = Self.defaultLens(in: capabilities)?.id ?? ""
        }
        settleSelections()
    }

    func capturePressed() {}

    private func settleSelections() {
        record = Self.settle(record, with: recordResolver) ?? record
        photo = Self.settle(photo, with: photoResolver) ?? photo
    }

    private func persist() {
        guard !isScripted else { return }
        SavedSelections(mode: mode, lensID: lensID, record: record, photo: photo).save(to: defaults)
    }

    private static func defaultLens(in capabilities: CaptureCapabilities) -> Lens? {
        capabilities.lenses.first { $0.kind == .wide && $0.zoomFactor == 1 } ?? capabilities.lenses.first
    }

    private static func settle(_ selection: RecordSelection?, with resolver: RecordSelectionResolver) -> RecordSelection? {
        selection.flatMap(resolver.settled) ?? resolver.defaultSelection()
    }

    private static func settle(_ selection: PhotoSelection?, with resolver: PhotoSelectionResolver) -> PhotoSelection? {
        selection.flatMap(resolver.settled) ?? resolver.defaultSelection()
    }
}
