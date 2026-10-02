import SSMTCore
import SwiftUI

extension CueKind {
    var icon: String {
        switch self {
        case .audio: return "waveform"
        case .fade: return "chart.line.downtrend.xyaxis"
        case .group: return "square.stack.3d.up"
        case .wait: return "hourglass"
        case .memo: return "note.text"
        case .start: return "play"
        case .stop: return "stop"
        case .pause: return "pause"
        case .load: return "tray.and.arrow.down"
        case .reset: return "arrow.counterclockwise"
        case .goTo: return "arrow.turn.down.right"
        case .target: return "scope"
        case .arm: return "checkmark.shield"
        case .disarm: return "xmark.shield"
        case .devamp: return "repeat.1"
        }
    }

    /// Kinds offered in the "add" menu, grouped.
    static let mediaKinds: [CueKind] = [.audio, .fade, .group, .wait, .memo]
    static let controlKinds: [CueKind] = [.start, .stop, .pause, .load, .reset, .goTo, .target, .arm, .disarm, .devamp]
}

/// Colour tags of cues.
enum CueColor: String, CaseIterable {
    case none = "", red, orange, yellow, green, blue, purple
    var color: Color {
        switch self {
        case .none: return .clear
        case .red: return Color(hex: 0xFF5F57)
        case .orange: return Color(hex: 0xFF9F0A)
        case .yellow: return Color(hex: 0xFFD60A)
        case .green: return Color(hex: 0x30D158)
        case .blue: return Color(hex: 0x64D2FF)
        case .purple: return Color(hex: 0xBF5AF2)
        }
    }
}

/// "1:05.3" style time.
func showTime(_ s: Double?) -> String {
    guard let s, s.isFinite else { return "∞" }
    let v = max(0, s)
    let m = Int(v) / 60
    let rest = v - Double(m * 60)
    return m > 0 ? String(format: "%d:%04.1f", m, rest) : String(format: "%.1f", rest)
}

/// Function #3: the show player.
struct ShowWorkspace: View {
    @EnvironmentObject var show: ShowStore
    @EnvironmentObject var loc: Localizer
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ShowTransport()
                .frame(width: 300)
            VStack(spacing: 10) {
                ShowHeader()
                if let e = show.lastError {
                    ErrorBanner(text: e.hasPrefix("error.") ? loc.t(e) : e) { show.lastError = nil }
                }
                CueListView()
            }
            .frame(maxWidth: .infinity)
            if !show.showMode {
                CueInspector()
                    .frame(width: 330)
            }
        }
        .onAppear {
            show.undo = undoManager
            show.localizer = loc
            show.isActive = true
            show.installKeyMonitor()
        }
        .onDisappear { show.isActive = false }
        .sheet(isPresented: $show.showSettings) {
            ShowSettingsView()
                .environmentObject(show)
                .environmentObject(loc)
                .preferredColorScheme(.dark)
        }
    }
}

// MARK: - Transport

/// Left column: what comes next, GO, what is playing, output meters.
struct ShowTransport: View {
    @EnvironmentObject var show: ShowStore
    @EnvironmentObject var loc: Localizer

    var body: some View {
        VStack(spacing: 12) {
            nextCard
            goButton
            HStack(spacing: 8) {
                Button {
                    show.anyPaused ? show.resumeAll() : show.pauseAll()
                } label: {
                    Label(loc.t(show.anyPaused ? "show.resumeAll" : "show.pauseAll"),
                          systemImage: show.anyPaused ? "play.fill" : "pause.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SSMTButtonStyle(active: show.anyPaused))
                .disabled(show.snapshot.running.isEmpty)
                Button { show.panic() } label: {
                    Label(loc.t("show.panic"), systemImage: "stop.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(SSMTButtonStyle(kind: .danger))
                .help(loc.t("show.panic.help"))
            }
            RunningCuesPanel()
            OutputMeters()
        }
    }

    private var nextCard: some View {
        let cue = show.doc.cue(show.snapshot.playhead ?? (show.snapshot == .empty ? show.currentList?.cues.first?.id : nil))
        return VStack(alignment: .leading, spacing: 6) {
            Text(loc.t("show.next").uppercased())
                .font(Theme.label(11)).tracking(1.2).foregroundStyle(Theme.textSecondary)
            if let cue {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(cue.number.isEmpty ? "·" : cue.number)
                        .font(Theme.numeral(40)).foregroundStyle(Theme.accent)
                        .lineLimit(1).minimumScaleFactor(0.5)
                    Image(systemName: cue.kind.icon).foregroundStyle(Theme.textSecondary)
                }
                Text(cue.name.isEmpty ? loc.t("cue.kind.\(cue.kind.rawValue)") : cue.name)
                    .font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                if !cue.notes.isEmpty {
                    Text(cue.notes).font(.system(size: 12)).foregroundStyle(Theme.textSecondary).lineLimit(4)
                }
            } else {
                Text(loc.t("show.endOfList")).font(.system(size: 16, weight: .medium)).foregroundStyle(Theme.textMuted)
                    .padding(.vertical, 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(padding: 16, highlighted: cue != nil)
    }

    private var goButton: some View {
        Button { show.go() } label: {
            VStack(spacing: 2) {
                Text("GO").font(.system(size: 40, weight: .heavy, design: .rounded)).tracking(4)
                Text(loc.t("show.go.hint")).font(.system(size: 11, weight: .medium)).opacity(0.65)
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 104)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.accent, Theme.accentHot], startPoint: .top, endPoint: .bottom))
            )
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.25)))
            .shadow(color: Theme.accent.opacity(0.35), radius: 16, y: 4)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .opacity(show.snapshot.playhead == nil && show.snapshot != .empty ? 0.4 : 1)
        .help(loc.t("show.go.help"))
    }
}

/// Cues waiting or playing, with progress and per-cue pause / stop.
struct RunningCuesPanel: View {
    @EnvironmentObject var show: ShowStore
    @EnvironmentObject var loc: Localizer

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(loc.t("show.running").uppercased()).font(Theme.label(11)).tracking(1.2).foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("\(show.snapshot.running.count)").font(Theme.mono(11)).foregroundStyle(Theme.textMuted)
            }
            if show.snapshot.running.isEmpty {
                Text(loc.t("show.running.none")).font(.system(size: 12)).foregroundStyle(Theme.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
            }
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(show.snapshot.running) { r in tile(r) }
                }
            }
            .frame(maxHeight: 320)
        }
        .glassCard(padding: 14)
    }

    private func tile(_ r: RunningCue) -> some View {
        let cue = show.doc.cue(r.id)
        let tint: Color = r.paused ? Theme.signalYellow : (r.phase == .preWait ? Theme.dataBlue : (r.phase == .stopping ? Theme.statusError : Theme.accent))
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: cue?.kind.icon ?? "questionmark").font(.system(size: 11)).foregroundStyle(tint).frame(width: 14)
                Text([cue?.number ?? "", cue?.name ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                Spacer(minLength: 4)
                if let it = r.iteration {
                    Text("×\(it)").font(Theme.mono(10)).foregroundStyle(Theme.textSecondary)
                }
                Text(r.phase == .preWait ? "▸ " + showTime(r.remaining) : "−" + showTime(r.remaining))
                    .font(Theme.mono(11)).foregroundStyle(tint)
                Button { show.togglePause(r.id) } label: { Image(systemName: r.paused ? "play.fill" : "pause.fill") }
                    .buttonStyle(.borderless).font(.system(size: 10))
                Button { show.stop(r.id) } label: { Image(systemName: "stop.fill") }
                    .buttonStyle(.borderless).font(.system(size: 10))
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule().fill(tint).frame(width: g.size.width * (r.progress ?? 1))
                        .opacity(r.progress == nil ? 0.35 : 1)
                }
            }
            .frame(height: 4)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.05)))
    }
}

/// Peak meters of the show outputs.
struct OutputMeters: View {
    @EnvironmentObject var show: ShowStore
    @EnvironmentObject var loc: Localizer

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(loc.t("show.outputs").uppercased()).font(Theme.label(11)).tracking(1.2).foregroundStyle(Theme.textSecondary)
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(show.doc.outputs.prefix(16).enumerated()), id: \.offset) { i, o in
                    let peak = i < show.meters.count ? Double(show.meters[i]) : 0
                    let db = peak > 0 ? 20 * log10(peak) : -100
                    let fill = max(0, min(1, (db + 60) / 60))
                    VStack(spacing: 3) {
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.07))
                            RoundedRectangle(cornerRadius: 2)
                                .fill(db > -3 ? Theme.statusError : (db > -12 ? Theme.signalYellow : Theme.accent))
                                .frame(height: 54 * fill)
                        }
                        .frame(height: 54)
                        Text(o.name).font(.system(size: 8)).foregroundStyle(Theme.textMuted).lineLimit(1)
                    }
                    .frame(maxWidth: 22)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(padding: 14)
    }
}

// MARK: - Header and toolbar

struct ShowHeader: View {
    @EnvironmentObject var show: ShowStore
    @EnvironmentObject var loc: Localizer
    @State private var showIssues = false

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                TextField(loc.t("show.name.placeholder"), text: Binding(get: { show.doc.name }, set: { v in show.edit { $0.name = v } }))
                    .textFieldStyle(.plain)
                    .font(Theme.heading(24))
                    .disabled(show.showMode)
                Spacer()
                statusChips
                Picker("", selection: $show.showMode) {
                    Label(loc.t("show.mode.edit"), systemImage: "pencil").tag(false)
                    Label(loc.t("show.mode.show"), systemImage: "lock.fill").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 230)
                .help(loc.t("show.mode.help"))
                Button { show.showSettings = true } label: { Image(systemName: "gearshape") }
                    .buttonStyle(SSMTButtonStyle())
                    .help(loc.t("show.settings"))
            }
            HStack(spacing: 6) {
                ForEach(show.doc.lists) { l in
                    let on = l.id == show.listID
                    Button { show.selectList(l.id) } label: {
                        Text(l.name).font(.system(size: 12, weight: on ? .semibold : .regular))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Capsule().fill(on ? Theme.accent.opacity(0.2) : Color.white.opacity(0.05)))
                            .foregroundStyle(on ? Theme.textPrimary : Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if !show.showMode {
                            Button(loc.t("show.list.rename")) { renameList(l.id) }
                            if show.doc.lists.count > 1 {
                                Button(loc.t("action.delete"), role: .destructive) {
                                    show.edit { $0.lists.removeAll { $0.id == l.id } }
                                }
                            }
                        }
                    }
                }
                if !show.showMode {
                    Button { show.addList() } label: { Image(systemName: "plus") }
                        .buttonStyle(.borderless).help(loc.t("show.list.add"))
                }
                Spacer()
            }
            if !show.showMode { ShowToolbar(showIssues: $showIssues) }
        }
        .glassCard(padding: 14)
    }

    private var statusChips: some View {
        HStack(spacing: 8) {
            chip(icon: show.outputError == nil ? "hifispeaker" : "exclamationmark.triangle.fill",
                 text: show.outputError == nil ? "\(show.outputName) · \(Int(show.sampleRate / 1000)) kHz" : loc.t("show.output.error"),
                 tint: show.outputError == nil ? Theme.textSecondary : Theme.statusError)
                .help(show.outputError ?? "")
            if show.memoryBytes > 0 {
                chip(icon: "memorychip", text: "\(show.memoryBytes / 1_048_576) MB", tint: Theme.textSecondary)
                    .help(loc.t("show.memory.help"))
            }
            if !show.missingFiles.isEmpty {
                Button { show.relinkMissing() } label: {
                    chip(icon: "questionmark.folder", text: String(format: loc.t("show.missing"), show.missingFiles.count), tint: Theme.statusWarning)
                }
                .buttonStyle(.plain)
                .help(loc.t("show.relink.help"))
            }
        }
    }

    private func chip(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 10))
            Text(text).font(.system(size: 11)).lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(Capsule().fill(Color.white.opacity(0.06)))
    }

    private func renameList(_ id: UUID) {
        let alert = NSAlert()
        alert.messageText = loc.t("show.list.rename")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = show.doc.lists.first { $0.id == id }?.name ?? ""
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: loc.t("action.cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue
        show.edit { d in if let i = d.lists.firstIndex(where: { $0.id == id }) { d.lists[i].name = name } }
    }
}

struct ShowToolbar: View {
    @EnvironmentObject var show: ShowStore
    @EnvironmentObject var loc: Localizer
    @Binding var showIssues: Bool

    var body: some View {
        HStack(spacing: 6) {
            Button { show.chooseAudioFiles() } label: { Label(loc.t("cue.kind.audio"), systemImage: "plus") }
                .buttonStyle(SSMTButtonStyle(kind: .primary))
                .help(loc.t("show.addAudio.help"))
            ForEach([CueKind.fade, .group, .wait, .stop, .memo], id: \.self) { k in
                tool(k.icon, loc.t("cue.kind.\(k.rawValue)")) { show.add(k) }
            }
            Menu {
                Section(loc.t("show.add.media")) {
                    ForEach(CueKind.mediaKinds, id: \.self) { k in
                        Button { k == .audio ? show.chooseAudioFiles() : show.add(k) } label: {
                            Label(loc.t("cue.kind.\(k.rawValue)"), systemImage: k.icon)
                        }
                    }
                }
                Section(loc.t("show.add.control")) {
                    ForEach(CueKind.controlKinds, id: \.self) { k in
                        Button { show.add(k) } label: { Label(loc.t("cue.kind.\(k.rawValue)"), systemImage: k.icon) }
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(loc.t("show.add.more"))
            Divider().frame(height: 22)
            let none = show.selection.isEmpty
            tool("plus.square.on.square", loc.t("action.duplicate")) { show.duplicateSelection() }.disabled(none)
            tool("arrow.up", loc.t("show.up")) { show.moveSelection(by: -1) }.disabled(none)
            tool("arrow.down", loc.t("show.down")) { show.moveSelection(by: 1) }.disabled(none)
            tool("square.stack.3d.up.slash", loc.t("show.ungroup")) { show.ungroupSelection() }
                .disabled(!show.selection.contains { show.doc.cue($0)?.kind == .group })
            tool("trash", loc.t("action.delete")) { show.deleteSelection() }.disabled(none)
            tool("list.number", loc.t("show.renumber")) { show.renumberSelection() }
            Spacer()
            Button { showIssues = true } label: {
                Label(loc.t("show.check"), systemImage: "checklist")
            }
            .buttonStyle(SSMTButtonStyle())
            .popover(isPresented: $showIssues, arrowEdge: .bottom) { ShowIssuesView().environmentObject(show).environmentObject(loc) }
        }
    }

    private func tool(_ icon: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).frame(width: 16) }
            .buttonStyle(SSMTButtonStyle())
            .help(help)
    }
}

/// Pre-show check.
struct ShowIssuesView: View {
    @EnvironmentObject var show: ShowStore
    @EnvironmentObject var loc: Localizer

    var body: some View {
        let issues = show.checkShow()
        VStack(alignment: .leading, spacing: 10) {
            Text(loc.t("show.check")).font(Theme.heading(15))
            if issues.isEmpty {
                Label(loc.t("show.check.ok"), systemImage: "checkmark.circle.fill").foregroundStyle(Theme.statusGood)
            }
            ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.statusWarning)
                    Text(text(issue)).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                }
                .onTapGesture { if let id = cueID(issue) { show.selection = [id] } }
            }
            if show.outputError != nil {
                Label(loc.t("show.output.error"), systemImage: "hifispeaker.slash").foregroundStyle(Theme.statusError)
            }
        }
        .padding(16)
        .frame(width: 380, alignment: .leading)
    }

    private func label(_ id: UUID) -> String {
        guard let c = show.doc.cue(id) else { return "?" }
        return [c.number, c.name.isEmpty ? loc.t("cue.kind.\(c.kind.rawValue)") : c.name].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func cueID(_ i: ShowIssue) -> UUID? {
        switch i {
        case let .missingTarget(id), let .missingFile(id), let .emptyGroup(id), let .invalidRegion(id): return id
        default: return nil
        }
    }

    private func text(_ i: ShowIssue) -> String {
        switch i {
        case let .missingTarget(id): return String(format: loc.t("show.issue.target"), label(id))
        case let .missingFile(id): return String(format: loc.t("show.issue.file"), label(id))
        case let .duplicateNumber(n): return String(format: loc.t("show.issue.number"), n)
        case let .duplicateHotkey(k): return String(format: loc.t("show.issue.hotkey"), k.uppercased())
        case let .emptyGroup(id): return String(format: loc.t("show.issue.emptyGroup"), label(id))
        case let .invalidRegion(id): return String(format: loc.t("show.issue.region"), label(id))
        }
    }
}
