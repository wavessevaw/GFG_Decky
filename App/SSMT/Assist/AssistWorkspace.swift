import SSMTAudio
import SSMTCore
import SwiftUI

/// Function #4: FOH Assist — the console connection, one-button group tuning, the channel list with
/// per-channel tuning, and what the assistant is doing in plain words.
struct AssistWorkspace: View {
    @EnvironmentObject var store: AssistStore
    @EnvironmentObject var loc: Localizer

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("FOH Assist").font(.system(size: 30, weight: .bold))
                        Text(loc.t("assist.subtitle")).font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    if store.running {
                        Button(loc.t("assist.stop")) { store.stopJob() }.buttonStyle(SSMTButtonStyle(kind: .danger))
                    }
                }
                if let m = store.message {
                    ErrorBanner(text: m == "nothing found" ? loc.t("assist.nothingFound") : m) { store.message = nil }
                }
                Picker("", selection: $store.mode) {
                    Text(loc.t("assist.mode.soundcheck")).tag(AssistStore.Mode.soundcheck)
                    Text(loc.t("assist.mode.show")).tag(AssistStore.Mode.show)
                    Text(loc.t("assist.mode.test")).tag(AssistStore.Mode.test)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 480)
                if store.mode == .test {
                    HStack(alignment: .top, spacing: 16) {
                        Panel(title: loc.t("assist.console"), tint: Theme.dataBlue) { ConnectionPanel() }
                        Panel(title: loc.t("assist.test"), tint: Theme.signalYellow) { ConsoleTestPanel() }
                            .frame(width: 460)
                    }
                    Panel(title: loc.t("assist.test.report"), tint: Theme.dataSecondary) { ConsoleTestReport() }
                } else if store.mode == .soundcheck {
                    HStack(alignment: .top, spacing: 16) {
                        Panel(title: loc.t("assist.console"), tint: Theme.dataBlue) { ConnectionPanel() }
                        Panel(title: loc.t("assist.oneButton"), tint: Theme.signalYellow) { GroupPanel() }
                            .frame(width: 400)
                    }
                    Panel(title: loc.t("assist.channels"), marking: "\(store.strips.count)") { AssistChannelTable() }
                    Panel(title: loc.t("assist.log"), tint: Theme.dataSecondary) { AssistLogView() }
                } else {
                    HStack(alignment: .top, spacing: 16) {
                        Panel(title: loc.t("assist.console"), tint: Theme.dataBlue) { ConnectionPanel() }
                        Panel(title: loc.t("assist.guard"), tint: Theme.signalYellow) { GuardPanel() }
                            .frame(width: 400)
                    }
                    Panel(title: loc.t("assist.guard.log"), tint: Theme.dataSecondary) { GuardLogView() }
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 24)
        }
    }
}

private struct ConnectionPanel: View {
    @EnvironmentObject var store: AssistStore
    @EnvironmentObject var loc: Localizer

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Picker(loc.t("assist.mixer"), selection: $store.family) {
                    ForEach(MixerFamily.allCases, id: \.self) { f in
                        Text(loc.t("assist.family.\(f.rawValue)") + (f.implemented ? "" : " — " + loc.t("assist.soon"))).tag(f)
                    }
                }
                .frame(width: 330)
                if store.family != .simulator {
                    TextField("192.168.1.64", text: $store.host).textFieldStyle(.roundedBorder).frame(width: 140)
                }
                Button(store.isConnected ? loc.t("assist.disconnect") : loc.t("assist.connect")) {
                    store.isConnected ? store.disconnect() : store.connect()
                }
                .buttonStyle(SSMTButtonStyle(kind: store.isConnected ? .secondary : .primary))
                .disabled(!store.family.implemented)
                status
            }
            if store.family != .simulator {
                Picker(loc.t("assist.source"), selection: $store.signalSource) {
                    Text(loc.t("assist.source.network")).tag(AssistStore.SignalSource.network)
                    Text(loc.t("assist.source.interface")).tag(AssistStore.SignalSource.interface)
                }
                .pickerStyle(.segmented)
                .frame(width: 520)
                .onChange(of: store.signalSource) { _ in store.restartCapture() }
                HStack(spacing: 10) {
                    Picker(loc.t("assist.audioIn"), selection: $store.inputDeviceUID) {
                        Text(loc.t("assist.systemInput")).tag(String?.none)
                        ForEach(store.inputDevices, id: \.uid) { d in Text("\(d.name) · \(d.inputChannels) in").tag(String?.some(d.uid)) }
                    }
                    .frame(width: 330)
                    .onChange(of: store.inputDeviceUID) { _ in store.restartCapture() }
                    if store.signalSource == .interface {
                        Stepper(String(format: loc.t("assist.firstInput"), store.firstInput), value: $store.firstInput, in: 1...64)
                    }
                    Stepper(store.micInput == 0 ? loc.t("assist.noMic") : String(format: loc.t("assist.micInput"), store.micInput),
                            value: $store.micInput, in: 0...64)
                        .onChange(of: store.micInput) { _ in store.restartCapture() }
                    Stepper(store.stageMicInput == 0 ? loc.t("assist.noStageMic") : String(format: loc.t("assist.stageMicInput"), store.stageMicInput),
                            value: $store.stageMicInput, in: 0...64)
                        .onChange(of: store.stageMicInput) { _ in store.restartCapture() }
                }
                .font(.system(size: 12))
                Text(loc.t(store.signalSource == .network ? "assist.networkHint" : "assist.audioHint"))
                    .font(.system(size: 11)).foregroundStyle(Theme.textMuted)
            }
            HStack(spacing: 10) {
                Picker(loc.t("assist.measMic"), selection: $store.micID) {
                    Text(loc.t("assist.measMic.fromSetup")).tag(UUID?.none)
                    ForEach(store.micChoices) { m in Text(m.typical ? m.name + " · " + loc.t("assist.typical") : m.name).tag(UUID?.some(m.id)) }
                }
                .frame(width: 420)
                if let l = store.micLevel {
                    Text(String(format: store.micCalibrated ? "%.0f dB(A)" : "%.0f dBFS(A)", l)).monospacedDigit()
                        .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                }
            }
            HStack(spacing: 10) {
                Picker(loc.t("assist.character"), selection: $store.character) {
                    ForEach(MixCharacter.allCases, id: \.self) { c in Text(loc.t("assist.char.\(c.rawValue)")).tag(c) }
                }
                .pickerStyle(.segmented)
                .frame(width: 420)
                Picker(loc.t("assist.tap"), selection: $store.tap) {
                    Text(loc.t("assist.tap.preEQ")).tag(TapPoint.preEQ)
                    Text(loc.t("assist.tap.postEQ")).tag(TapPoint.postEQ)
                }
                .frame(width: 260)
            }
            Text(loc.t("assist.char.\(store.character.rawValue).hint")).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
        }
    }

    @ViewBuilder private var status: some View {
        switch store.connection {
        case .disconnected: StatusBadge(level: .idle, text: loc.t("assist.offline"))
        case .connecting: StatusBadge(level: .warning, text: loc.t("assist.connecting"))
        case let .connected(t): StatusBadge(level: .good, text: t)
        case let .failed(t): StatusBadge(level: .error, text: t == "not supported yet" ? loc.t("assist.soon") : t)
        }
    }
}

private struct GroupPanel: View {
    @EnvironmentObject var store: AssistStore
    @EnvironmentObject var loc: Localizer

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button { store.tune(.orchestra) } label: { Label(loc.t("assist.orchestra"), systemImage: "music.quarternote.3") }
                    .buttonStyle(SSMTButtonStyle(kind: .primary))
                Button { store.tune(.choir) } label: { Label(loc.t("assist.choir"), systemImage: "person.3.fill") }
                    .buttonStyle(SSMTButtonStyle(kind: .primary))
            }
            .disabled(!store.isConnected || store.running)
            HStack(spacing: 8) {
                Button { store.checkPolarity() } label: { Label(loc.t("assist.polarity"), systemImage: "plusminus.circle") }
                    .buttonStyle(SSMTButtonStyle())
            }
            .disabled(!store.isConnected || store.running)
            HStack(spacing: 6) {
                Text(loc.t("assist.range")).font(.system(size: 12))
                Stepper("\(store.rangeFrom)", value: $store.rangeFrom, in: 1...max(1, store.strips.count))
                Text("—")
                Stepper("\(store.rangeTo)", value: $store.rangeTo, in: 1...max(1, store.strips.count))
                Button(loc.t("assist.rangeGo")) { store.tune(.range(store.rangeFrom, store.rangeTo)) }
                    .buttonStyle(SSMTButtonStyle())
                    .disabled(!store.isConnected || store.running)
            }
            if let p = store.groupPhase {
                StatusBadge(level: p == .done ? .good : .warning, text: loc.t("assist.phase.\(p.rawValue)"))
            }
            Text(loc.t("assist.groupHint")).font(.system(size: 11)).foregroundStyle(Theme.textMuted)
            Button(loc.t("assist.undoAll")) { store.undoAll() }.buttonStyle(SSMTButtonStyle()).disabled(!store.isConnected)
        }
    }
}

private struct AssistChannelTable: View {
    @EnvironmentObject var store: AssistStore
    @EnvironmentObject var loc: Localizer

    var body: some View {
        VStack(spacing: 0) {
            header
            ForEach(store.strips) { s in row(s) }
        }
        .font(.system(size: 12))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("#").frame(width: 28, alignment: .trailing)
            Text(loc.t("assist.col.name")).frame(width: 120, alignment: .leading)
            Text(loc.t("assist.col.source")).frame(width: 130, alignment: .leading)
            Text(loc.t("assist.col.gain")).frame(width: 56, alignment: .trailing)
            Text("HPF").frame(width: 56, alignment: .trailing)
            Text("EQ").frame(minWidth: 220, alignment: .leading)
            Text(loc.t("assist.col.comp")).frame(width: 120, alignment: .leading)
            Text(loc.t("assist.col.fader")).frame(width: 56, alignment: .trailing)
            Spacer()
            Text(loc.t("assist.col.state")).frame(width: 190, alignment: .trailing)
        }
        .foregroundStyle(Theme.textMuted)
        .padding(.vertical, 6)
    }

    private func row(_ s: ChannelStrip) -> some View {
        let state = store.state(of: s.id)
        return HStack(spacing: 8) {
            Text("\(s.id)").monospacedDigit().frame(width: 28, alignment: .trailing).foregroundStyle(Theme.textMuted)
            Text(s.name.isEmpty ? "—" : s.name).lineLimit(1).frame(width: 120, alignment: .leading)
            Text(store.kind(of: s.id).map { loc.t("assist.kind.\($0.rawValue)") } ?? "—").lineLimit(1)
                .frame(width: 130, alignment: .leading).foregroundStyle(Theme.textSecondary)
            Text(String(format: "%.1f", s.gainDB) + (s.polarityInverted ? " Ø" : "")).monospacedDigit().frame(width: 56, alignment: .trailing)
            Text(s.highPassOn ? String(format: "%.0f", s.highPassHz) : "off").monospacedDigit().frame(width: 56, alignment: .trailing)
            Text(eqSummary(s)).lineLimit(1).frame(minWidth: 220, alignment: .leading).foregroundStyle(Theme.textSecondary)
            Text(s.compressor.enabled ? String(format: "%.0f dB %.1f:1", s.compressor.thresholdDB, s.compressor.ratio) : "off")
                .monospacedDigit().frame(width: 120, alignment: .leading)
            Text(s.faderDB <= -90 ? "-∞" : String(format: "%.1f", s.faderDB)).monospacedDigit().frame(width: 56, alignment: .trailing)
            Spacer()
            HStack(spacing: 6) {
                switch state {
                case .done?: StatusBadge(level: .good, text: loc.t("assist.state.done"))
                case .listening?: StatusBadge(level: .warning, text: loc.t("assist.state.listening"))
                case .tuning?: StatusBadge(level: .warning, text: loc.t("assist.state.tuning"))
                default: EmptyView()
                }
                Button(loc.t("assist.tuneOne")) { store.tune(channel: s.id) }
                    .buttonStyle(SSMTButtonStyle())
                    .disabled(!store.isConnected || store.running)
            }
            .frame(width: 190, alignment: .trailing)
        }
        .padding(.vertical, 4)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    private func eqSummary(_ s: ChannelStrip) -> String {
        guard s.eqOn else { return "off" }
        let bands = s.eq.filter { abs($0.gainDB) >= 0.5 }
        if bands.isEmpty { return "flat" }
        return bands.map { String(format: "%@ %+.1f", PEQFilter.label($0.frequency), $0.gainDB) }.joined(separator: " · ")
    }
}

private struct AssistLogView: View {
    @EnvironmentObject var store: AssistStore
    @EnvironmentObject var loc: Localizer

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if store.log.isEmpty {
                Text(loc.t("assist.log.empty")).font(.system(size: 12)).foregroundStyle(Theme.textMuted)
            }
            ForEach(Array(store.log.suffix(40).reversed().enumerated()), id: \.offset) { _, e in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(e.channel)").monospacedDigit().frame(width: 28, alignment: .trailing).foregroundStyle(Theme.textMuted)
                    Text(store.strips.first { $0.id == e.channel }?.name ?? "").frame(width: 110, alignment: .leading).lineLimit(1)
                    Text(text(e.note)).foregroundStyle(color(e.note))
                }
                .font(.system(size: 12))
            }
        }
    }

    private func text(_ n: AssistNote) -> String {
        switch n {
        case .waitingForSignal: return loc.t("assist.note.waiting")
        case let .recognised(k, c): return String(format: loc.t("assist.note.recognised"), loc.t("assist.kind.\(k.rawValue)"), Int(c * 100))
        case let .gain(a, b): return String(format: loc.t("assist.note.gain"), a, b)
        case let .clipRisk(p): return String(format: loc.t("assist.note.clip"), p)
        case let .highPass(hz): return String(format: loc.t("assist.note.hpf"), hz)
        case let .eqBand(i, t, f, g, q):
            let type = t == .peaking ? String(format: "Q %.1f", q) : loc.t(t == .lowShelf ? "assist.lowShelf" : "assist.highShelf")
            return String(format: loc.t("assist.note.eq"), i + 1, PEQFilter.label(f), g, type)
        case let .compressor(thr, r, a, rel, gr): return String(format: loc.t("assist.note.comp"), thr, r, a, rel, gr)
        case .compressorOff: return loc.t("assist.note.compOff")
        case let .fader(db): return String(format: loc.t("assist.note.fader"), db)
        case let .feedback(f, d): return String(format: loc.t("assist.note.feedback"), PEQFilter.label(f), d)
        case let .polarityChecking(ref):
            return String(format: loc.t("assist.note.polChecking"), store.strips.first { $0.id == ref }?.name ?? "\(ref)")
        case let .polarity(inv, d): return String(format: loc.t(inv ? "assist.note.polInverted" : "assist.note.polKept"), d)
        case let .polarityUnclear(d): return String(format: loc.t("assist.note.polUnclear"), d)
        case let .done(dev): return String(format: loc.t("assist.note.done"), dev)
        case let .gaveUp(r): return loc.t(r == "no signal" ? "assist.note.noSignal" : "assist.note.unsettled")
        }
    }

    private func color(_ n: AssistNote) -> Color {
        switch n {
        case .done: return Theme.statusGood
        case .polarity: return Theme.statusGood
        case .feedback, .clipRisk, .gaveUp, .polarityUnclear: return Theme.statusWarning
        default: return Theme.textPrimary
        }
    }
}

private struct GuardPanel: View {
    @EnvironmentObject var store: AssistStore
    @EnvironmentObject var loc: Localizer

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if store.guarding {
                    Button { store.stopGuard() } label: { Label(loc.t("assist.guard.off"), systemImage: "shield.slash") }
                        .buttonStyle(SSMTButtonStyle(kind: .danger))
                    StatusBadge(level: .good, text: String(format: loc.t("assist.guard.active"), store.guardian?.activeCorrections ?? 0))
                } else {
                    Button { store.startGuard() } label: { Label(loc.t("assist.guard.on"), systemImage: "shield.lefthalf.filled") }
                        .buttonStyle(SSMTButtonStyle(kind: .primary))
                        .disabled(!store.isConnected)
                }
            }
            Text(loc.t("assist.guard.hint")).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            if let g = store.guardian {
                Text(loc.t("assist.guard.monitors")).font(Theme.label(12)).foregroundStyle(Theme.textSecondary)
                FlowRow(items: store.buses.map { ($0.id, $0.name.isEmpty ? "Bus \($0.id)" : $0.name, g.monitorBuses.contains($0.id)) }) { id, on in
                    store.setMonitor(id, on)
                }
                Text(loc.t("assist.guard.leads")).font(Theme.label(12)).foregroundStyle(Theme.textSecondary)
                FlowRow(items: store.strips.filter { !$0.name.isEmpty }.map { ($0.id, $0.name, g.leads.contains($0.id)) }) { id, on in
                    store.setLead(id, on)
                }
            }
        }
    }
}

/// Toggle chips that wrap onto as many lines as needed.
private struct FlowRow: View {
    let items: [(Int, String, Bool)]
    let toggle: (Int, Bool) -> Void

    var body: some View {
        let rows = stride(from: 0, to: items.count, by: 4).map { Array(items[$0..<min($0 + 4, items.count)]) }
        VStack(alignment: .leading, spacing: 4) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 4) {
                    ForEach(rows[r], id: \.0) { item in
                        Button(item.1) { toggle(item.0, !item.2) }
                            .buttonStyle(SSMTButtonStyle(active: item.2))
                            .lineLimit(1)
                    }
                }
            }
        }
    }
}

private struct GuardLogView: View {
    @EnvironmentObject var store: AssistStore
    @EnvironmentObject var loc: Localizer

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if store.guardLog.isEmpty {
                Text(loc.t("assist.guard.empty")).font(.system(size: 12)).foregroundStyle(Theme.textMuted)
            }
            ForEach(Array(store.guardLog.suffix(40).reversed().enumerated()), id: \.offset) { _, e in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(String(format: "%02d:%02d", Int(e.time) / 60, Int(e.time) % 60)).monospacedDigit()
                        .frame(width: 46, alignment: .trailing).foregroundStyle(Theme.textMuted)
                    Text(text(e.action))
                }
                .font(.system(size: 12))
            }
        }
    }

    private func name(_ ch: Int) -> String { store.strips.first { $0.id == ch }?.name ?? "\(ch)" }
    private func bus(_ id: Int) -> String { store.buses.first { $0.id == id }.map { $0.name.isEmpty ? "Bus \(id)" : $0.name } ?? "Bus \(id)" }

    private func text(_ a: GuardAction) -> String {
        switch a {
        case let .notch(ch, f, d): return String(format: loc.t("assist.g.notch"), name(ch), PEQFilter.label(f), d)
        case let .notchReleased(ch): return String(format: loc.t("assist.g.notchReleased"), name(ch))
        case let .monitorDip(b, d): return String(format: loc.t("assist.g.dip"), bus(b), d)
        case let .monitorRestored(b): return String(format: loc.t("assist.g.restored"), bus(b))
        case let .monitorHeld(b, d): return String(format: loc.t("assist.g.held"), bus(b), d)
        case let .unmask(ch, f, d): return String(format: loc.t("assist.g.unmask"), name(ch), PEQFilter.label(f), d)
        case let .unmaskReleased(ch): return String(format: loc.t("assist.g.unmaskReleased"), name(ch))
        case let .tonalHold(ch, f, d): return String(format: loc.t("assist.g.tonal"), name(ch), PEQFilter.label(f), d)
        case let .tonalReleased(ch): return String(format: loc.t("assist.g.tonalReleased"), name(ch))
        case let .yielded(ch, b): return String(format: loc.t("assist.g.yielded"), ch.map(name) ?? b.map(bus) ?? "")
        }
    }
}

private struct ConsoleTestPanel: View {
    @EnvironmentObject var store: AssistStore
    @EnvironmentObject var loc: Localizer

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(loc.t("assist.test.hint")).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            Picker(loc.t("assist.test.scenario"), selection: $store.testScenario) {
                ForEach(AssistScenario.all) { s in Text(loc.t("assist.scenario.\(s.id)") + " · \(s.channels.count) ch").tag(s.id) }
            }
            .frame(width: 400)
            Stepper(String(format: loc.t("assist.test.first"), store.testFirst), value: $store.testFirst, in: 1...32)
                .font(.system(size: 12))
            Toggle(loc.t("assist.test.muteMain"), isOn: $store.testMuteMain).font(.system(size: 12))
            Label(loc.t("assist.test.warning"), systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 11)).foregroundStyle(Theme.statusWarning)
            HStack {
                Button { store.runConsoleTest() } label: {
                    Label(store.testing ? loc.t("assist.test.running") : loc.t("assist.test.run"), systemImage: "checklist")
                }
                .buttonStyle(SSMTButtonStyle(kind: .primary))
                .disabled(store.testing || (store.family != .simulator && !store.isConnected))
                if store.testing { ProgressView().controlSize(.small) }
            }
        }
    }
}

private struct ConsoleTestReport: View {
    @EnvironmentObject var store: AssistStore
    @EnvironmentObject var loc: Localizer

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if store.testChecks.isEmpty {
                Text(loc.t("assist.test.empty")).font(.system(size: 12)).foregroundStyle(Theme.textMuted)
            }
            ForEach(store.testChecks) { c in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    StatusBadge(level: level(c.status), text: loc.t("assist.test.status.\(c.status.rawValue)"))
                        .frame(width: 110, alignment: .leading)
                    Text(loc.t("assist.test.step.\(c.id)")).font(.system(size: 12, weight: .semibold)).frame(width: 230, alignment: .leading)
                    Text(c.detail).font(.system(size: 12)).foregroundStyle(Theme.textSecondary).textSelection(.enabled)
                }
            }
        }
    }

    private func level(_ s: ConsoleTestCheck.Status) -> StatusLevel {
        switch s {
        case .ok: return .good
        case .warning, .running: return .warning
        case .failed: return .error
        }
    }
}
