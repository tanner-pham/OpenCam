import CoreGraphics
import CoreImage
import Foundation
import Observation
import OSLog

/// One photo being edited: its saved edit, a screen-sized proxy of the original, and the preview rendered from that proxy.
/// The original file is never rendered here and never rewritten; Done writes the edit beside it.
@MainActor @Observable final class EditorModel {
    static let proxyLongSide = 2048
    private static let logger = Logger(subsystem: "local.opencam.app", category: "EditorModel")

    let item: LibraryItem
    var group: EditorGroup
    var isShowingOriginal = false
    private let edits: EditStore
    /// Used by the Looks group (Task 8).
    private let lookStore: LookStore
    private let renderer: LookRenderer
    /// The preview render; `renderer.renderedCGImage` unless a test replaces it.
    private let renderPreview: @Sendable (CIImage, Adjustments) async -> CGImage?

    var adjustments = Adjustments() {
        didSet { if adjustments != oldValue { requestRender() } }
    }
    private(set) var lookName: String?
    private(set) var phase: EditorPhase = .loading

    /// The edit rendered on the proxy.
    private(set) var preview: CGImage?
    /// The proxy without the edit.
    private(set) var original: CGImage?
    private(set) var proxySize: CGSize?
    /// What `preview` shows.
    private(set) var renderedAdjustments: Adjustments?
    /// Width x height of the image the last completed render returned, measured on that image.
    private(set) var lastRenderPixelSize: CGSize?
    /// Completed preview renders, the first one included.
    private(set) var previewRenderCount = 0

    /// The edit as it was loaded or last saved.
    private var savedEdit = PhotoEdit()
    private var proxy: CIImage?
    private var renders = RenderCoalescer<Adjustments>()
    private var renderTask: Task<Void, Never>?
    private var shownGeneration = 0

    /// `renderPreview` is a test seam for a render that fails; the app never passes it.
    init(item: LibraryItem, edits: EditStore, looks: LookStore, group: EditorGroup = .light, renderer: LookRenderer = .shared,
         renderPreview: (@Sendable (CIImage, Adjustments) async -> CGImage?)? = nil) {
        self.item = item
        self.edits = edits
        self.lookStore = looks
        self.group = group
        self.renderer = renderer
        self.renderPreview = renderPreview ?? { image, adjustments in await renderer.renderedCGImage(image, adjustments: adjustments) }
    }

    var hasChanges: Bool { adjustments != savedEdit.adjustments || lookName != savedEdit.lookName }

    /// Changes that leaving without Done would lose. A photo that cannot be edited (any failed phase) has none to lose.
    var hasUnsavedChanges: Bool {
        if case .failed = phase { return false }
        return hasChanges
    }

    /// Reads the edit (an unreadable one counts as none), decodes the proxy off the main actor and renders the first preview.
    /// An edit from a newer version leaves the photo read-only and decodes nothing.
    func load() async {
        let edit: PhotoEdit
        do {
            edit = try edits.load(stem: item.stem)
        } catch {
            Self.logger.error("\(error.description, privacy: .public)")
            edit = PhotoEdit()
        }
        savedEdit = edit
        lookName = edit.lookName
        adjustments = edit.adjustments
        guard edit.version <= PhotoEdit.currentVersion else {
            Self.logger.error("[EditorModel:load] Edit is from a newer version, so the photo opens read-only — {stem: \(self.item.stem, privacy: .public), version: \(edit.version)}")
            phase = .failed(LibraryCopy.newerEdit)
            return
        }
        let decoded: CIImage
        do {
            decoded = try await PictureDecoder.proxy(at: item.pictureURL, longSide: Self.proxyLongSide)
        } catch {
            Self.logger.error("\(error.description, privacy: .public)")
            phase = .failed(LibraryCopy.cannotOpen)
            return
        }
        guard let unedited = await renderer.cgImage(decoded) else {
            Self.logger.error("[EditorModel:load] The proxy could not be drawn — {path: \(self.item.pictureURL.path(percentEncoded: false), privacy: .public)}")
            phase = .failed(LibraryCopy.cannotOpen)
            return
        }
        proxy = decoded
        proxySize = decoded.extent.size
        original = unedited
        requestRender()
        await waitForPreview()
        guard preview != nil else {
            // The render already logged why; without a first picture the photo cannot be edited.
            phase = .failed(LibraryCopy.cannotOpen)
            return
        }
        phase = .ready
    }

    /// Returns when no render is running or waiting.
    func waitForPreview() async {
        while !renders.isIdle, let task = renderTask {
            await task.value
        }
    }

    func reset(_ key: AdjustmentKey) {
        adjustments[key] = 0
    }

    /// Also clears the look.
    func resetAll() {
        adjustments = Adjustments()
        lookName = nil
    }

    /// Writes the edit beside the original (an empty edit removes the file). False, with the phase saying why, when the photo is
    /// read-only or gone or the file cannot be written; nothing is written then.
    func save() -> Bool {
        if case .failed = phase { return false }
        let path = item.pictureURL.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else {
            Self.logger.error("[EditorModel:save] The original is gone, so the edit was not saved — {path: \(path, privacy: .public)}")
            phase = .failed(LibraryCopy.cannotOpen)
            return false
        }
        guard hasChanges else { return true }
        let edit = PhotoEdit(adjustments: adjustments, lookName: lookName)
        do {
            try edits.save(edit, stem: item.stem)
        } catch {
            Self.logger.error("\(error.description, privacy: .public)")
            if case .newerVersion = error { phase = .failed(LibraryCopy.newerEdit) } else { phase = .failed(LibraryCopy.saveFailed) }
            return false
        }
        savedEdit = edit
        return true
    }

    /// Starts a render of the current adjustments, or leaves them waiting in place of any earlier value while one runs.
    private func requestRender() {
        guard proxy != nil, let job = renders.request(adjustments) else { return }
        renderTask = Task { await runRenders(from: job) }
    }

    /// Renders the job, then whatever latest value waited meanwhile, until nothing waits. Every render takes the in-memory proxy.
    private func runRenders(from first: (generation: Int, value: Adjustments)) async {
        var job: (generation: Int, value: Adjustments)? = first
        while let current = job {
            if let proxy, let image = await renderPreview(proxy, current.value) {
                show(image, adjustments: current.value, generation: current.generation)
            } else {
                Self.logger.error("[EditorModel:runRenders] The preview could not be rendered — {stem: \(self.item.stem, privacy: .public)}")
            }
            job = renders.finish()
        }
    }

    /// A result older than the one on screen is dropped.
    private func show(_ image: CGImage, adjustments rendered: Adjustments, generation: Int) {
        guard generation > shownGeneration else { return }
        shownGeneration = generation
        preview = image
        renderedAdjustments = rendered
        lastRenderPixelSize = CGSize(width: image.width, height: image.height)
        previewRenderCount += 1
    }
}
