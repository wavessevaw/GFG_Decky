import AppKit
import Combine
import Foundation
import SSMTAudio
import SSMTCore
import UniformTypeIdentifiers

/// The playback side, confined to one serial queue: engine, mixer clock and audio output.
private final class PlaybackCore: @unchecked Sendable {
    let queue = DispatchQueue(label: "ssmt.show.engine", qos: .userInteractive)
    var engine: ShowEngine?
    var output: ShowAudioOutput?
    var timer: DispatchSourceTimer?
    let clips = ClipCache()
    var ticks = 0
    /// Folder for relative file paths (the show file's URL).
    var showURL: URL?

    var now: Int64 { Int64(output?.mixer.framesRendered.value ?? 0) }
}

/// The open show: document with undo, file handling, selection, and the link to the playback engine.
@MainActor
final class ShowStore: ObservableObject {
    @Published var doc: ShowDocument {
        didSet { if doc != oldValue { documentEdited() } }
    }
    @Published private(set) var fileURL: URL? {
        didSet { let u = fileURL; core.queue.async { [core] in core.showURL = u } }
    }
    @Published var selection = Set<Cue.ID>()
    @Published var listID: UUID?
    @Published var collapsed = Set<Cue.ID>()
    /// Show mode: editing locked, big transport, keyboard GO.
    @Published var showMode = false
    @Published var showSettings = false
    @Published private(set) var snapshot = ShowSnapshot.empty
    @Published private(set) var meters: [Float] = []
    @Published private(set) var outputName = ""
    @Published private(set) var outputError: String?
    @Published private(set) var sampleRate: Double = 48000
    @Published private(set) var memoryBytes = 0
    /// Clip lengths (seconds) and channel counts by resolved path, for the list and inspector.
    @Published private(set) var clipInfo: [String: (duration: Double, channels: Int)] = [:]
    @Published private(set) var missingFiles = Set<String>()
    @Published var lastError: String?
    /// The section is visible (keyboard shortcuts active).
    var isActive = false {
        didSet { if isActive && !outputStarted { outputStarted = true; restartOutput() } }
    }
    private var outputStarted = false

    weak var undo: UndoManager?
    /// Set by the workspace; used for undo action names and messages.
    weak var localizer: Localizer?
    private let core = PlaybackCore()
    private var autosaveWork: DispatchWorkItem?
    private var keyMonitor: Any?

    static let fileType = UTType(filenameExtension: "ssmtshow", conformingTo: .json) ?? .json
    static let audioTypes: [UTType] = [.audio, .mp3, .wav, .aiff, .mpeg4Audio]

    private static var autosaveURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SSMT", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("show-autosave.json")
    }

    init(startAudio: Bool = true) {
        if let data = try? Data(contentsOf: Self.autosaveURL), let d = try? ShowDocument.decode(data) {
            doc = d
        } else {
            doc = ShowDocument(name: "")
        }
        listID = doc.lists.first?.id
        if startAudio { outputStarted = true; restartOutput() }
    }

    /// For previews and snapshot tests: a document without audio output.
    init(document: ShowDocument) {
        doc = document
        listID = document.lists.first?.id
        outputStarted = true // never opens an audio device
    }

    var currentList: CueList? { doc.list(listID) }

    /// Snapshot tests: no audio device, and a fixed playback state to render.
    func preview(snapshot: ShowSnapshot, clips: [String: (duration: Double, channels: Int)], meters: [Float]) {
        outputStarted = true
        self.snapshot = snapshot
        clipInfo = clips
        self.meters = meters
        missingFiles = []
        outputName = "Preview"
    }

    // MARK: Editing with undo

    func edit(_ name: String = "", _ change: (inout ShowDocument) -> Void) {
        guard !showMode else { return }
        let before = doc
        change(&doc)
        guard doc != before, let undo else { return }
        undo.registerUndo(withTarget: self) { store in
            MainActor.assumeIsolated { store.restore(before) }
        }
        undo.setActionName(name)
    }

    private func restore(_ state: ShowDocument) {
        let current = doc
        doc = state
        undo?.registerUndo(withTarget: self) { store in
            MainActor.assumeIsolated { store.restore(current) }
        }
    }

    private func documentEdited() {
        let d = doc
        core.queue.async { [core] in core.engine?.document = d }
        if listID == nil || !doc.lists.contains(where: { $0.id == listID }) { listID = doc.lists.first?.id }
        scheduleAutosave()
        refreshFiles()
    }

    // MARK: Cue creation

    /// Adds a cue after the selection (targeting the selected cue when the kind needs a target).
    func add(_ kind: CueKind) {
        guard let lid = listID else { return }
        var c = Cue(kind: kind, number: kind == .memo || kind == .group ? "" : doc.nextCueNumber)
        let anchor = lastSelected
        if kind.needsTarget, let a = anchor, let target = doc.cue(a) {
            if doc.targetCandidates(for: kind, excluding: c.id).contains(where: { $0.id == target.id }) {
                c.target = target.id
            }
        }
        if kind == .group, selection.count > 1 {
            var newID: UUID?
            edit { newID = $0.group(Array(selection), list: lid) }
            selection = newID.map { [$0] } ?? []
            return
        }
        edit { $0.insert([c], after: anchor, list: lid) }
        selection = [c.id]
    }

    /// The last selected cue in show order.
    var lastSelected: UUID? {
        guard let list = currentList else { return nil }
        return list.cues.flattened().map(\.cue.id).last { selection.contains($0) }
    }

    /// Selected cues in show order.
    var orderedSelection: [UUID] {
        guard let list = currentList else { return [] }
        return list.cues.flattened().map(\.cue.id).filter { selection.contains($0) }
    }

    func addAudioFiles(_ urls: [URL], after: UUID? = nil, intoGroup: UUID? = nil) {
        guard let lid = listID, !urls.isEmpty else { return }
        var number = Double(doc.nextCueNumber) ?? 1
        let cues: [Cue] = urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }.map {
            defer { number += 1 }
            return Cue.audio(file: storedPath(for: $0), number: String(Int(number)))
        }
        edit {
            if let g = intoGroup { $0.append(cues, toGroup: g) } else { $0.insert(cues, after: after ?? lastSelected, list: lid) }
        }
        selection = Set(cues.map(\.id))
    }

    func chooseAudioFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Self.audioTypes
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        addAudioFiles(panel.urls)
    }

    func chooseFile(for cueID: UUID) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Self.audioTypes
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let path = storedPath(for: url)
        edit { d in
            d.updateCue(cueID) { c in
                c.audio?.file = path
                if c.name.isEmpty { c.name = url.deletingPathExtension().lastPathComponent }
            }
        }
    }

    func deleteSelection() {
        let ids = selection
        edit(loc("action.delete")) { $0.delete(ids) }
        selection = []
    }

    func duplicateSelection() {
        guard let lid = listID else { return }
        var copies: [UUID] = []
        let ids = orderedSelection
        edit { copies = $0.duplicate(ids, list: lid) }
        selection = Set(copies)
    }

    func moveSelection(by delta: Int) {
        guard let lid = listID else { return }
        let ids = delta < 0 ? orderedSelection : orderedSelection.reversed()
        edit { d in ids.forEach { d.move($0, by: delta, list: lid) } }
    }

    func ungroupSelection() {
        guard let lid = listID else { return }
        let groups = orderedSelection.filter { doc.cue($0)?.kind == .group }
        edit { d in groups.forEach { d.ungroup($0, list: lid) } }
    }

    func renumberSelection() {
        guard let lid = listID else { return }
        let ids = selection.isEmpty ? nil : orderedSelection
        edit { $0.renumber(ids, list: lid) }
    }

    func addList() {
        let l = CueList(name: "\(loc("show.list")) \(doc.lists.count + 1)")
        edit { $0.lists.append(l) }
        selectList(l.id)
    }

    func selectList(_ id: UUID) {
        listID = id
        selection = []
        core.queue.async { [core] in core.engine?.selectList(id) }
    }

    func updateCue(_ id: UUID, _ change: @escaping (inout Cue) -> Void) {
        edit { $0.updateCue(id, change) }
    }

    // MARK: Transport

    func go() { run { e, now in e.go(now: now) } }
    func panic() { run { e, now in e.panic(now: now) } }
    func pauseAll() { run { e, now in e.pauseAll(now: now) } }
    func resumeAll() { run { e, now in e.resumeAll(now: now) } }
    func start(_ id: UUID) { run { e, now in e.start(id, now: now) } }
    func stop(_ id: UUID) { run { e, now in e.stop(id, now: now) } }
    func togglePause(_ id: UUID) {
        let paused = snapshot.running.first { $0.id == id }?.paused ?? false
        run { e, now in paused ? e.resume(id, now: now) : e.pause(id, now: now) }
    }
    func setPlayhead(_ id: UUID?) { run { e, _ in e.setPlayhead(id) } }

    var anyPaused: Bool { snapshot.running.contains { $0.paused } }

    private func run(_ action: @escaping (ShowEngine, Int64) -> Void) {
        core.queue.async { [core] in
            guard let e = core.engine else { return }
            action(e, core.now)
        }
    }

    // MARK: Audio output

    /// (Re)creates the output on the show's interface and a new engine at its sample rate.
    func restartOutput() {
        let d = doc
        let core = self.core
        core.queue.async {
            core.timer?.cancel()
            core.output?.stop()
            core.output = nil
            var errorText: String?
            do {
                core.output = try ShowAudioOutput(deviceUID: d.deviceUID, maxOutputs: 64)
            } catch {
                errorText = "\(error)"
            }
            let sr = core.output?.sampleRate ?? 48000
            let mixer = core.output?.mixer
            mixer?.send(.patch(d.outputs.map { $0.deviceChannel ?? -1 }))
            let clips = core.clips
            let engine = ShowEngine(document: d, sampleRate: sr, lookahead: Int64(sr * 0.03),
                                    send: { op in mixer?.send(op) },
                                    clipProvider: { cue in
                                        guard let path = cue.audio.map({ ShowStore.resolve($0.file, showURL: core.showURL) }) else { return nil }
                                        return clips.cached(path, sampleRate: sr) ?? clips.load(path, sampleRate: sr)
                                    })
            engine.preload = { cue in
                if let f = cue.audio?.file { clips.load(ShowStore.resolve(f, showURL: core.showURL), sampleRate: sr) }
            }
            engine.documentChanged = { [weak self] newDoc in
                Task { @MainActor in self?.doc = newDoc }
            }
            core.engine = engine
            let name = core.output?.deviceName ?? ""
            let timer = DispatchSource.makeTimerSource(queue: core.queue)
            timer.schedule(deadline: .now(), repeating: .milliseconds(5), leeway: .milliseconds(1))
            timer.setEventHandler { [weak self] in
                guard let e = core.engine else { return }
                e.advance(to: core.now)
                core.output?.mixer.collectGarbage()
                core.ticks += 1
                if core.ticks % 8 == 0 {
                    let snap = e.snapshot(now: core.now)
                    let peaks = core.output?.mixer.takePeaks() ?? []
                    Task { @MainActor in self?.apply(snap, peaks: peaks) }
                }
            }
            timer.resume()
            core.timer = timer
            Task { @MainActor [weak self] in
                self?.outputName = name
                self?.outputError = errorText
                self?.sampleRate = sr
                self?.refreshFiles(load: true)
            }
        }
    }

    private func apply(_ snap: ShowSnapshot, peaks: [Float]) {
        if snap != snapshot { snapshot = snap }
        let used = Array(peaks.prefix(doc.outputs.count))
        if used != meters { meters = used }
        if let lid = snap.listID, lid != listID, doc.lists.contains(where: { $0.id == lid }) { listID = lid }
    }

    // MARK: Files

    /// Absolute path of a cue's file (relative paths are resolved against the show file's folder).
    nonisolated static func resolve(_ path: String, showURL: URL?) -> String {
        if path.hasPrefix("/") { return path }
        if let base = showURL?.deletingLastPathComponent() { return base.appendingPathComponent(path).path }
        return path
    }

    func resolvedPath(_ cue: Cue) -> String? {
        guard let f = cue.audio?.file, !f.isEmpty else { return nil }
        return Self.resolve(f, showURL: fileURL)
    }

    /// Paths are stored absolute; files next to the show file are stored relative to it.
    private func storedPath(for url: URL) -> String {
        if let base = fileURL?.deletingLastPathComponent().path, url.path.hasPrefix(base + "/") {
            return String(url.path.dropFirst(base.count + 1))
        }
        return url.path
    }

    /// Checks files and (optionally) decodes them in the background so GO never waits for disk.
    private func refreshFiles(load: Bool = true) {
        let paths = Set(doc.allCues.compactMap { resolvedPath($0) })
        missingFiles = Set(paths.filter { !FileManager.default.fileExists(atPath: $0) })
        guard load else { return }
        let sr = sampleRate
        let core = self.core
        let todo = paths.subtracting(missingFiles).filter { clipInfo[$0] == nil || core.clips.cached($0, sampleRate: sr) == nil }
        guard !todo.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var info: [String: (Double, Int)] = [:]
            for p in todo {
                if let c = core.clips.load(p, sampleRate: sr) { info[p] = (c.duration, c.channelCount) }
            }
            core.clips.forget(except: paths)
            let bytes = core.clips.totalBytes
            Task { @MainActor in
                guard let self else { return }
                for (k, v) in info { self.clipInfo[k] = (duration: v.0, channels: v.1) }
                self.memoryBytes = bytes
            }
        }
    }

    /// Looks for missing files by name inside a folder (recursively) and relinks them.
    func relinkMissing() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        var found: [String: URL] = [:]
        if let e = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil) {
            for case let url as URL in e { found[url.lastPathComponent.lowercased()] = url }
        }
        var relinked = 0
        let missing = missingFiles
        edit(loc("show.relink")) { d in
            for c in d.allCues {
                guard let f = c.audio?.file, missing.contains(Self.resolve(f, showURL: self.fileURL)),
                      let url = found[(f as NSString).lastPathComponent.lowercased()] else { continue }
                let path = self.storedPath(for: url)
                d.updateCue(c.id) { $0.audio?.file = path }
                relinked += 1
            }
        }
        lastError = String(format: loc("show.relink.done"), relinked)
    }

    /// Pre-show check: problems as readable lines.
    func checkShow() -> [ShowIssue] {
        doc.issues { cue in
            guard let p = resolvedPath(cue) else { return false }
            return FileManager.default.fileExists(atPath: p)
        }
    }

    // MARK: Documents

    func newDocument() {
        guard !showMode else { return }
        run { e, now in e.panic(now: now, hard: true) }
        edit { $0 = ShowDocument(name: "") }
        fileURL = nil
        selection = []
        listID = doc.lists.first?.id
    }

    func open() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [Self.fileType, .json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let d = try ShowDocument.decode(Data(contentsOf: url))
            run { e, now in e.panic(now: now, hard: true) }
            fileURL = url
            edit { $0 = d }
            listID = d.lists.first?.id
            selection = []
            restartOutput()
        } catch {
            lastError = "\(url.lastPathComponent): \(error)"
        }
    }

    func save(as: Bool = false) {
        var url = fileURL
        if url == nil || `as` {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [Self.fileType]
            panel.nameFieldStringValue = (doc.name.isEmpty ? "Show" : doc.name) + ".ssmtshow"
            guard panel.runModal() == .OK, let u = panel.url else { return }
            url = u
        }
        guard let url else { return }
        do {
            try doc.encoded().write(to: url, options: .atomic)
            fileURL = url
        } catch {
            lastError = "\(url.lastPathComponent): \(error)"
        }
    }

    private func scheduleAutosave() {
        autosaveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let data = try? self.doc.encoded() else { return }
            try? data.write(to: Self.autosaveURL, options: .atomic)
        }
        autosaveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    // MARK: Keyboard

    /// Space = GO, Esc = panic (twice = cut), cue hotkeys; ignored while typing in a text field.
    func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return MainActor.assumeIsolated { self.handleKey(event) ? nil : event }
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard isActive else { return false }
        if let responder = NSApp.keyWindow?.firstResponder, responder is NSText || responder is NSTextView { return false }
        let mods = event.modifierFlags.intersection([.command, .control, .option])
        guard mods.isEmpty else { return false }
        switch event.keyCode {
        case 49: go(); return true            // space
        case 53: panic(); return true         // esc
        default: break
        }
        guard let ch = event.charactersIgnoringModifiers?.lowercased(), !ch.isEmpty else { return false }
        if let cue = doc.allCues.first(where: { ($0.hotkey ?? "").lowercased() == ch }) {
            start(cue.id)
            return true
        }
        return false
    }

    private func loc(_ key: String) -> String { localizer?.t(key) ?? key }
}
