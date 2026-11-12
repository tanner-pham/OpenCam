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
    var group: EditorGroup {
        didSet { if group != oldValue { requestMaskOverlay() } }
    }
    /// The curve the Curve group shows and edits.
    var curveChannel: CurveChannel = .master
    /// The colour band the Mix group shows; never saved, so an edit opens on Red.
    var mixBand: ColourBand = .red
    /// The tonal range the Grading group shows; never saved, so an edit opens on Midtones.
    var gradingRegion: GradingRegion = .midtones
    var isShowingOriginal = false
    private let edits: EditStore
    private let lookStore: LookStore
    private let renderer: LookRenderer
    private let exporter: PhotoExporter
    /// The preview render; `renderer.renderedCGImage` unless a test replaces it.
    private let renderPreview: @Sendable (CIImage, PhotoEdit, CIImage?) async -> CGImage?
    /// Finds the photo's subject on the proxy; `SubjectMasker.mask(for:)` unless a test replaces it.
    private let findSubject: @Sendable (CIImage) async -> CIImage?
    /// The histogram count; `PictureHistogram.make(from:)` unless a test replaces it.
    private let makeHistogram: @Sendable (CGImage) async -> PictureHistogram?
    /// The name of a look to apply, unsaved, once the photo has loaded (`-editorLook` for screenshots); nil for a tap.
    private let launchLook: String?

    var adjustments = Adjustments() {
        didSet {
            guard adjustments != oldValue else { return }
            record(PhotoEdit(adjustments: oldValue, lookName: lookName, masks: masks))
            requestRender()
        }
    }
    private(set) var lookName: String? {
        didSet { if lookName != oldValue { record(PhotoEdit(adjustments: adjustments, lookName: oldValue, masks: masks)) } }
    }
    /// The local masks, in the order they are drawn; edited through `addMask`, `deleteSelectedMask` and `updateSelectedMask`.
    private(set) var masks: [LocalMask] = [] {
        didSet {
            guard masks != oldValue else { return }
            record(PhotoEdit(adjustments: adjustments, lookName: lookName, masks: oldValue))
            requestRender()
            requestMaskOverlay()
            requestSubject()
        }
    }
    /// Whether the photo's subject has been looked for: `.notNeeded` until a subject mask first exists, then once per open.
    private(set) var subjectState: SubjectState = .notNeeded
    /// The brush's size, 1...100, and whether it erases; editor settings, neither saved nor undoable.
    var brushSize = 30.0
    var isErasing = false
    /// The brush's radius as a fraction of the picture's shorter side, 0.01...0.15.
    var brushRadius: Double { 0.01 + (min(max(brushSize, 1), 100) - 1) / 99 * 0.14 }
    /// The mask the Masks group shows; never saved. An edit opens with its last mask chosen, as does an undo or redo that
    /// leaves none chosen.
    var selectedMaskID: UUID? {
        didSet {
            guard selectedMaskID != oldValue else { return }
            endStroke()
            requestMaskOverlay()
        }
    }
    /// Whether the selected mask is tinted red on the picture while the Masks group is open.
    var isShowingMaskOverlay = true {
        didSet { if isShowingMaskOverlay != oldValue { requestMaskOverlay() } }
    }
    /// The selected mask in translucent red at the proxy's size; nil when it is not shown or the mask cannot apply.
    private(set) var maskOverlay: CGImage?
    var selectedMask: LocalMask? { masks.first { $0.id == selectedMaskID } }
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
    private(set) var renderedEdit: PhotoEdit?
    var renderedAdjustments: Adjustments? { renderedEdit?.adjustments }
    /// Width x height of the image the last completed render returned, measured on that image.
    private(set) var lastRenderPixelSize: CGSize?
    /// Completed preview renders, the first one included.
    private(set) var previewRenderCount = 0
    /// The histogram of the newest preview counted so far; nil until the first count finishes.
    private(set) var histogram: PictureHistogram?

    /// The edit as it was loaded or last saved.
    private var savedEdit = PhotoEdit()
    private var history = EditHistory()
    /// True while `restore(_:)` writes the edit, so an undo or redo is not recorded as a change.
    private var isRestoring = false
    private var isStroking = false
    private var hasRecordedStroke = false
    private var strokeBuilder: BrushStrokeBuilder?
    private var strokeMaskID: UUID?
    /// Where the open stroke sits in its mask's strokes, recorded by `beginStroke`.
    private var strokeIndex = 0
    private let now: @Sendable () -> Date
    private var proxy: CIImage?
    private var subject: CIImage?
    private var subjectTask: Task<Void, Never>?
    private var renders = RenderCoalescer<PhotoEdit>()
    private var renderTask: Task<Void, Never>?
    private var overlays = RenderCoalescer<MaskOverlayKey?>()
    private var overlayTask: Task<Void, Never>?
    private var requestedOverlay: MaskOverlayKey?
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

    /// `renderPreview` is a test seam for a render that fails, `makeHistogram` one for a slow count and `findSubject` one for
    /// a subject that Vision would not find in a drawn test picture; the app passes none of them.
    /// `launchLook` names a look in `looks` that is applied through `applyLook(_:)`, unsaved, after a successful load.
    init(item: LibraryItem, edits: EditStore, looks: LookStore, group: EditorGroup = .light, renderer: LookRenderer = .shared,
         exporter: PhotoExporter = .appDefault(), renderPreview: (@Sendable (CIImage, PhotoEdit, CIImage?) async -> CGImage?)? = nil,
         makeHistogram: (@Sendable (CGImage) async -> PictureHistogram?)? = nil, launchLook: String? = nil,
         findSubject: (@Sendable (CIImage) async -> CIImage?)? = nil, now: (@Sendable () -> Date)? = nil) {
        self.now = now ?? { Date() }
        self.item = item
        self.edits = edits
        self.lookStore = looks
        self.group = group
        self.renderer = renderer
        self.exporter = exporter
        self.renderPreview = renderPreview ?? { image, edit, subject in await renderer.renderedCGImage(image, edit: edit, subject: subject) }
        self.findSubject = findSubject ?? { image in await SubjectMasker.mask(for: image) }
        self.makeHistogram = makeHistogram ?? { image in await PictureHistogram.make(from: image) }
        self.launchLook = launchLook
    }

    /// The edit as shown; with `restore(_:)`, the one place the model's edit state is read and written.
    var currentEdit: PhotoEdit { PhotoEdit(adjustments: adjustments, lookName: lookName, masks: masks) }

    private func restore(_ edit: PhotoEdit) {
        closeStroke()
        isRestoring = true
        defer { isRestoring = false }
        adjustments = edit.adjustments
        lookName = edit.lookName
        masks = edit.masks
        if selectedMask == nil { selectedMaskID = masks.last?.id }
    }

    private func record(_ before: PhotoEdit) {
        guard !isRestoring else { return }
        // A stroke in progress is one step however long the finger pauses: only its first write records.
        if isStroking {
            if hasRecordedStroke { return }
            hasRecordedStroke = true
        }
        history.record(before, at: now())
    }

    var canUndo: Bool { history.canUndo }
    var canRedo: Bool { history.canRedo }

    func undo() {
        closeStroke()
        if let previous = history.undo(from: currentEdit) { restore(previous) }
    }

    func redo() {
        closeStroke()
        if let next = history.redo(from: currentEdit) { restore(next) }
    }

    var hasChanges: Bool { !adjustments.matches(savedEdit.adjustments) || lookName != savedEdit.lookName || masks != savedEdit.masks }

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
        restore(edit)
        history.clear()
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
        requestMaskOverlay()
        requestSubject()
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

    /// Returns when the subject search and the renders it leads to have finished.
    func waitForSubject() async {
        await subjectTask?.value
        await waitForPreview()
        await waitForMaskOverlay()
    }

    /// Returns when no mask overlay render is running or waiting.
    func waitForMaskOverlay() async {
        while !overlays.isIdle, let task = overlayTask {
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

    /// Sets one grading wheel's hue and saturation in a single write to `adjustments`, so a drag renders once per move.
    func setWheel(_ region: GradingRegion, hue: Double, saturation: Double) {
        var edited = adjustments
        edited[region.hueKey] = hue
        edited[region.saturationKey] = saturation
        adjustments = edited
    }

    /// Takes one grading wheel's puck back to the centre (hue and saturation 0); its luminance keeps its own reset.
    func resetWheel(_ region: GradingRegion) {
        setWheel(region, hue: 0, saturation: 0)
    }

    /// Also clears the look.
    func resetAll() {
        history.breakStep()
        adjustments = Adjustments()
        lookName = nil
        masks = []
        selectedMaskID = nil
        history.breakStep()
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
        let edit = currentEdit
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

    /// Starts a render of the current edit, or leaves it waiting in place of any earlier value while one runs.
    private func requestRender() {
        guard proxy != nil, let job = renders.request(currentEdit) else { return }
        renderTask = Task { await runRenders(from: job) }
    }

    /// Renders the job, then whatever latest value waited meanwhile, until nothing waits. Every render takes the in-memory proxy.
    private func runRenders(from first: (generation: Int, value: PhotoEdit)) async {
        var job: (generation: Int, value: PhotoEdit)? = first
        while let current = job {
            if let proxy, let image = await renderPreview(proxy, current.value, subject) {
                show(image, edit: current.value, generation: current.generation)
            } else {
                Self.logger.error("[EditorModel:runRenders] The preview could not be rendered — {stem: \(self.item.stem, privacy: .public)}")
            }
            job = renders.finish()
        }
    }

    /// A result older than the one on screen is dropped.
    private func show(_ image: CGImage, edit rendered: PhotoEdit, generation: Int) {
        guard generation > shownGeneration else { return }
        shownGeneration = generation
        preview = image
        renderedEdit = rendered
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

// MARK: - Masks

extension EditorModel {
    /// Adds a mask of `kind` with its default shape and no adjustments, and selects it. One undo step.
    func addMask(_ kind: MaskKind) {
        let mask = LocalMask(shape: kind.defaultShape)
        endStroke()
        history.breakStep()
        masks.append(mask)
        selectedMaskID = mask.id
        history.breakStep()
    }

    /// Removes the selected mask and selects the one before it, or none. One undo step.
    func deleteSelectedMask() {
        guard let index = masks.firstIndex(where: { $0.id == selectedMaskID }) else { return }
        endStroke()
        history.breakStep()
        masks.remove(at: index)
        selectedMaskID = masks.indices.contains(index - 1) ? masks[index - 1].id : masks.first?.id
        history.breakStep()
    }

    /// Flips the selected mask's Invert as a step of its own, so it never merges into a slider move just before or after it.
    func toggleSelectedMaskInverted() {
        history.breakStep()
        updateSelectedMask { $0.isInverted.toggle() }
        history.breakStep()
    }

    /// Changes the selected mask in one write to `masks`, so a drag renders once per move and coalesces like any slider.
    func updateSelectedMask(_ change: (inout LocalMask) -> Void) {
        guard let index = masks.firstIndex(where: { $0.id == selectedMaskID }) else { return }
        var edited = masks
        change(&edited[index])
        masks = edited
    }
}

// MARK: - Brush

extension EditorModel {
    /// Starts a stroke in the selected brush mask; does nothing when the selection is not a brush. Not undoable until `endStroke`
    /// closes it: the whole stroke is one step.
    func beginStroke(at point: MaskPoint, pressure: Double?) {
        guard !isStroking, let mask = selectedMask, case .brush = mask.shape else { return }
        var builder = BrushStrokeBuilder(radius: brushRadius, isErasing: isErasing)
        guard builder.add(point, pressure: pressure) else { return }
        history.breakStep()
        isStroking = true
        hasRecordedStroke = false
        strokeBuilder = builder
        strokeMaskID = mask.id
        let stroke = builder.stroke
        if case let .brush(strokes) = mask.shape { strokeIndex = strokes.count }
        writeStroke { (strokes: inout [BrushStroke]) in strokes.append(stroke) }
    }

    func continueStroke(at point: MaskPoint, pressure: Double?) {
        guard isStroking, var builder = strokeBuilder, builder.add(point, pressure: pressure) else { return }
        strokeBuilder = builder
        let stroke = builder.stroke
        let at = strokeIndex
        writeStroke { (strokes: inout [BrushStroke]) in
            if at == strokes.count { strokes.append(stroke) } else { strokes[at] = stroke }
        }
    }

    func endStroke() {
        guard isStroking else { return }
        closeStroke()
        history.breakStep()
    }

    /// Drops the open stroke's state without touching the history, for an undo, redo or restore that replaces the edit.
    private func closeStroke() {
        isStroking = false
        strokeBuilder = nil
        strokeMaskID = nil
    }

    /// One write to `masks` per sample, so the picture renders once per sample. The stroke goes back to the index `beginStroke`
    /// recorded; when its mask or that place no longer exists the stroke ends and nothing is written.
    private func writeStroke(_ change: (inout [BrushStroke]) -> Void) {
        guard let index = masks.firstIndex(where: { $0.id == strokeMaskID }), case var .brush(strokes) = masks[index].shape,
              strokeIndex <= strokes.count else {
            closeStroke()
            return
        }
        change(&strokes)
        var edited = masks
        edited[index].shape = .brush(strokes: strokes)
        masks = edited
    }
}

// MARK: - Looks

extension EditorModel {
    /// Long side of a look tile's picture, in pixels.
    nonisolated static let tileLongSide = 240

    /// An edit like any other: copies the look's values and name into the edit, which renders through the preview path.
    /// Nil clears the edit and the look.
    func applyLook(_ look: Look?) {
        history.breakStep()
        adjustments = look?.adjustments ?? Adjustments()
        lookName = look?.name
        history.breakStep()
    }

    /// Saves the current values as a new look, which the edit then names as its look.
    func saveAsLook(named name: String) throws(LookStoreError) -> Look {
        let look = try lookStore.save(name: name, adjustments: adjustments)
        // Naming the edit changes no picture, so it is not an undo step, but it does end the redo steps.
        history.clearRedo()
        isRestoring = true
        lookName = look.name
        isRestoring = false
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
            return try await exporter.export(item, edit: currentEdit)
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

// MARK: - Mask overlay

/// What the overlay depends on: the mask's shape and inversion. Its adjustments do not change it.
private nonisolated struct MaskOverlayKey: Equatable, Sendable {
    let shape: MaskShape
    let isInverted: Bool
    /// A subject mask draws once the subject is found.
    let hasSubject: Bool
}

extension EditorModel {
    /// Renders the overlay for the selected mask when it differs from the last one asked for, one render at a time.
    fileprivate func requestMaskOverlay() {
        let wanted: MaskOverlayKey? = group == .masks && isShowingMaskOverlay
            ? selectedMask.map { MaskOverlayKey(shape: $0.shape, isInverted: $0.isInverted, hasSubject: subject != nil) } : nil
        guard wanted != requestedOverlay else { return }
        // Recorded only once it can start: a request made before the proxy decodes is asked for again when the proxy is ready.
        guard let proxy else { return }
        requestedOverlay = wanted
        // Nothing to draw clears at once; a render still running is dropped when it ends, as it no longer matches the request.
        if wanted == nil { maskOverlay = nil }
        guard let job = overlays.request(wanted) else { return }
        overlayTask = Task { await runOverlays(from: job, extent: proxy.extent) }
    }

    fileprivate func runOverlays(from first: (generation: Int, value: MaskOverlayKey?), extent: CGRect) async {
        var job: (generation: Int, value: MaskOverlayKey?)? = first
        while let current = job {
            let image = await renderOverlay(current.value, extent: extent, subject: subject)
            // Only the newest request decides what is shown, so a stale result never replaces a clear.
            if current.value == requestedOverlay { maskOverlay = image }
            job = overlays.finish()
        }
    }

    private func renderOverlay(_ key: MaskOverlayKey?, extent: CGRect, subject: CIImage?) async -> CGImage? {
        guard let key else { return nil }
        let mask = LocalMask(shape: key.shape, isInverted: key.isInverted)
        let renderer = renderer
        return await Self.overlayImage(renderer: renderer, mask: mask, extent: extent, subject: subject)
    }

    @concurrent private static func overlayImage(renderer: LookRenderer, mask: LocalMask, extent: CGRect, subject: CIImage?) async -> CGImage? {
        guard let overlay = renderer.maskOverlay(for: mask, extent: extent, subject: subject) else { return nil }
        return await renderer.cgImage(overlay)
    }
}

// MARK: - Subject

/// Where the search for the photo's subject stands.
nonisolated enum SubjectState: Equatable, Sendable {
    case notNeeded, finding, found, notFound
}

extension EditorModel {
    /// Looks for the subject on the proxy, off the main actor, the first time any subject mask exists. Once per open: a photo
    /// where nothing was found is not searched again. A found subject brings the preview and the overlay up to date.
    fileprivate func requestSubject() {
        guard subjectState == .notNeeded, let proxy, masks.contains(where: { $0.shape.kind == .subject }) else { return }
        subjectState = .finding
        let find = findSubject
        subjectTask = Task {
            let found = await find(proxy)
            subject = found
            subjectState = found == nil ? .notFound : .found
            guard found != nil else { return }
            requestRender()
            requestMaskOverlay()
        }
    }
}
