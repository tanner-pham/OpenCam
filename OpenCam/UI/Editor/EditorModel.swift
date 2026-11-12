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
    /// The curve the Curve group shows and edits.
    var curveChannel: CurveChannel = .master
    var isShowingOriginal = false
    private let edits: EditStore
    private let lookStore: LookStore
    private let renderer: LookRenderer
    private let exporter: PhotoExporter
    /// The preview render; `renderer.renderedCGImage` unless a test replaces it.
    private let renderPreview: @Sendable (CIImage, Adjustments) async -> CGImage?
    /// The histogram count; `PictureHistogram.make(from:)` unless a test replaces it.
    private let makeHistogram: @Sendable (CGImage) async -> PictureHistogram?
    /// The name of a look to apply, unsaved, once the photo has loaded (`-editorLook` for screenshots); nil for a tap.
    private let launchLook: String?

    var adjustments = Adjustments() {
        didSet { if adjustments != oldValue { requestRender() } }
    }
    private(set) var lookName: String?
    /// The lens and exposure facts of the original file; none until the read finishes or when the file carries none.
    private(set) var facts = PhotoFacts.none
    var designation: FormatDesignation? { FormatDesignation.of(item) }
    private(set) var phase: EditorPhase = .loading
    /// The saved looks, as `LookStore.all()` orders them.
    private(set) var looks: [Look] = []
    /// A message for the editor's alert; cleared when the alert closes.
    var alertMessage: String?
    /// True while `export()` renders and writes the file.
    private(set) var isExporting = false

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
    /// The histogram of the newest preview counted so far; nil until the first count finishes.
    private(set) var histogram: PictureHistogram?

    /// The edit as it was loaded or last saved.
    private var savedEdit = PhotoEdit()
    private var proxy: CIImage?
    private var renders = RenderCoalescer<Adjustments>()
    private var renderTask: Task<Void, Never>?
    private var shownGeneration = 0
    private var histograms = RenderCoalescer<CGImage>()
    private var histogramTask: Task<Void, Never>?
    private var countedGeneration = 0

    /// The unedited proxy at `tileLongSide`, which every look tile is rendered from.
    private var tileSource: CIImage?
    /// Each tile's render by the adjustments it shows, kept while the editor is open; a renamed look reuses its tile.
    private var tiles: [Adjustments: Task<CGImage?, Never>] = [:]
    /// The tile render started last; the next one waits for it, so tiles draw one at a time.
    private var lastTile: Task<CGImage?, Never>?

    /// `renderPreview` is a test seam for a render that fails, `makeHistogram` one for a slow count; the app never passes either.
    /// `launchLook` names a look in `looks` that is applied through `applyLook(_:)`, unsaved, after a successful load.
    init(item: LibraryItem, edits: EditStore, looks: LookStore, group: EditorGroup = .light, renderer: LookRenderer = .shared,
         exporter: PhotoExporter = .appDefault(), renderPreview: (@Sendable (CIImage, Adjustments) async -> CGImage?)? = nil,
         makeHistogram: (@Sendable (CGImage) async -> PictureHistogram?)? = nil, launchLook: String? = nil) {
        self.item = item
        self.edits = edits
        self.lookStore = looks
        self.group = group
        self.renderer = renderer
        self.exporter = exporter
        self.renderPreview = renderPreview ?? { image, adjustments in await renderer.renderedCGImage(image, adjustments: adjustments) }
        self.makeHistogram = makeHistogram ?? { image in await PictureHistogram.make(from: image) }
        self.launchLook = launchLook
    }

    var hasChanges: Bool { !adjustments.matches(savedEdit.adjustments) || lookName != savedEdit.lookName }

    /// Changes that leaving without Done would lose. A photo that cannot be edited (any failed phase) has none to lose.
    var hasUnsavedChanges: Bool {
        if case .failed = phase { return false }
        return hasChanges
    }

    /// Reads the edit, decodes the proxy off the main actor and renders the first preview. An edit from a newer version, or
    /// one that cannot be read, leaves the photo read-only and decodes nothing: this build never overwrites such a file.
    func load() async {
        // Started first, so the read never delays the decode; a read-only photo still shows its facts.
        async let readFacts = PhotoFacts.read(at: item.pictureURL)
        await loadPhoto()
        facts = await readFacts
    }

    private func loadPhoto() async {
        looks = lookStore.all()
        let edit: PhotoEdit
        do {
            edit = try edits.load(stem: item.stem)
        } catch {
            Self.logger.error("\(error.description, privacy: .public)")
            switch error {
            case .newerVersion: phase = .failed(LibraryCopy.newerEdit)
            case .unreadable, .unwritable: phase = .failed(LibraryCopy.unreadableEdit)
            }
            return
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
        tileSource = await Self.makeTileSource(from: unedited)
        requestRender()
        await waitForPreview()
        guard preview != nil else {
            // The render already logged why; without a first picture the photo cannot be edited.
            phase = .failed(LibraryCopy.cannotOpen)
            return
        }
        phase = .ready
        if let launchLook {
            if let look = looks.first(where: { $0.name == launchLook }) {
                applyLook(look)
            } else {
                Self.logger.error("[EditorModel:load] No look has the launch look's name, so none was applied — {look: \(launchLook, privacy: .public)}")
            }
        }
    }

    /// Returns when no render is running or waiting.
    func waitForPreview() async {
        while !renders.isIdle, let task = renderTask {
            await task.value
        }
    }

    /// Returns when no histogram count is running or waiting.
    func waitForHistogram() async {
        while !histograms.isIdle, let task = histogramTask {
            await task.value
        }
    }

    func reset(_ key: AdjustmentKey) {
        adjustments[key] = 0
    }

    /// Straightens one channel's curve; the other curves stay.
    func resetCurve(_ channel: CurveChannel) {
        adjustments.curves[channel] = .identity
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
            switch error {
            case .newerVersion: phase = .failed(LibraryCopy.newerEdit)
            case .unreadable: phase = .failed(LibraryCopy.unreadableEdit)
            case .unwritable: phase = .failed(LibraryCopy.saveFailed)
            }
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
        requestHistogram(of: image)
    }

    /// Counts the newest preview at a lower priority; the preview path never awaits it, and a count still waiting is replaced.
    private func requestHistogram(of image: CGImage) {
        guard let job = histograms.request(image) else { return }
        histogramTask = Task(priority: .utility) { await runHistograms(from: job) }
    }

    private func runHistograms(from first: (generation: Int, value: CGImage)) async {
        var job: (generation: Int, value: CGImage)? = first
        while let current = job {
            if let counted = await makeHistogram(current.value) {
                if current.generation > countedGeneration {
                    countedGeneration = current.generation
                    histogram = counted
                }
            } else {
                Self.logger.error("[EditorModel:runHistograms] The histogram could not be counted — {stem: \(self.item.stem, privacy: .public)}")
            }
            job = histograms.finish()
        }
    }
}

// MARK: - Looks

extension EditorModel {
    /// Long side of a look tile's picture, in pixels.
    nonisolated static let tileLongSide = 240

    /// An edit like any other: copies the look's values and name into the edit, which renders through the preview path.
    /// Nil clears the edit and the look.
    func applyLook(_ look: Look?) {
        adjustments = look?.adjustments ?? Adjustments()
        lookName = look?.name
    }

    /// Saves the current values as a new look, which the edit then names as its look.
    func saveAsLook(named name: String) throws(LookStoreError) -> Look {
        let look = try lookStore.save(name: name, adjustments: adjustments)
        lookName = look.name
        refreshLooks()
        return look
    }

    /// The Save of the name alert: renames `look` when the alert was opened for one, else saves the current values as a new
    /// look. `look` is the value the alert was presented with, so dismissing the alert cannot change which of the two runs.
    func saveLookName(_ name: String, renaming look: Look?) throws(LookStoreError) {
        if let look {
            try renameLook(look.id, to: name)
        } else {
            _ = try saveAsLook(named: name)
        }
    }

    /// The edit keeps the name it copied, as photos in the library do.
    func renameLook(_ id: UUID, to name: String) throws(LookStoreError) {
        defer { refreshLooks() }
        _ = try lookStore.rename(id, to: name)
    }

    func duplicateLook(_ id: UUID) throws(LookStoreError) {
        defer { refreshLooks() }
        _ = try lookStore.duplicate(id)
    }

    /// The current edit keeps its values and look name: a look is copied into an edit, never linked.
    func deleteLook(_ id: UUID) throws(LookStoreError) {
        defer { refreshLooks() }
        try lookStore.delete(id)
    }

    /// The look (nil: no edit) on the unedited photo at `tileLongSide`, rendered off the main actor, one tile at a time and at
    /// a lower priority than the preview, with its own colour table. Nil while the photo is not loaded or when the render fails.
    func lookPreview(_ look: Look?) async -> CGImage? {
        let values = look?.adjustments ?? Adjustments()
        if let existing = tiles[values] { return await existing.value }
        guard let source = tileSource else { return nil }
        let previous = lastTile
        let renderer = renderer
        let task = Task(priority: .utility) {
            _ = await previous?.value
            return await renderer.renderedCGImageWithOwnTable(source, adjustments: values)
        }
        tiles[values] = task
        lastTile = task
        let image = await task.value
        if image == nil {
            Self.logger.error("[EditorModel:lookPreview] A look tile could not be rendered — {stem: \(self.item.stem, privacy: .public), look: \(look?.name ?? "None", privacy: .public)}")
            tiles[values] = nil
        }
        return image
    }

    /// Reads the looks again and drops tiles no look shows any more.
    private func refreshLooks() {
        looks = lookStore.all()
        let shown = Set(looks.map(\.adjustments)).union([Adjustments()])
        tiles = tiles.filter { shown.contains($0.key) }
    }

    /// The unedited proxy redrawn at `tileLongSide`, off the main actor.
    @concurrent private static func makeTileSource(from image: CGImage) async -> CIImage? {
        PictureDecoder.capped(image, longSide: tileLongSide).map { CIImage(cgImage: $0) }
    }
}

// MARK: - Export

extension EditorModel {
    /// Export works once the photo is loaded and editable. A read-only photo (edited by a newer version) does not export:
    /// this version would bake in only the part of that edit it can read.
    var canExport: Bool { phase == .ready && !isExporting }

    /// Writes the edit as currently shown, unsaved changes included, to a new full-size file for sharing; the original and
    /// the saved edit are not touched. The full-size render runs in `PhotoExporter`, never through the preview path.
    /// Nil on failure: a missing original fails the editor, anything else sets `alertMessage`.
    func export() async -> URL? {
        guard canExport else { return nil }
        isExporting = true
        defer { isExporting = false }
        do {
            return try await exporter.export(item, edit: PhotoEdit(adjustments: adjustments, lookName: lookName))
        } catch {
            Self.logger.error("\(error.description, privacy: .public)")
            if case .sourceMissing = error { phase = .failed(LibraryCopy.cannotOpen) } else { alertMessage = LibraryCopy.exportFailed }
            return nil
        }
    }

    /// Removes an exported file once the share sheet has closed; whatever the person saved or sent is a copy.
    func discardExport(at url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            Self.logger.error("[EditorModel:discardExport] The export file could not be removed — {file: \(url.lastPathComponent, privacy: .public), reason: \(error.localizedDescription, privacy: .public)}")
        }
    }
}
