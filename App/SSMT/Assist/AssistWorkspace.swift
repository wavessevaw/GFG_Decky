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
                HStack(alignment: .top, spacing: 16) {
                    Panel(title: loc.t("assist.console"), tint: Theme.dataBlue) { ConnectionPanel() }
                    Panel(title: loc.t("assist.oneButton"), tint: Theme.signalYellow) { GroupPanel() }
                        .frame(width: 400)
                }
                Panel(title: loc.t("assist.channels"), marking: "\(store.strips.count)") { AssistChannelTable() }
                Panel(title: loc.t("assist.log"), tint: Theme.dataSecondary) { AssistLogView() }
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
                HStack(spacing: 10) {
                    Picker(loc.t("assist.audioIn"), selection: $store.inputDeviceUID) {
                        Text(loc.t("assist.systemInput")).tag(String?.none)
                        ForEach(store.inputDevices, id: \.uid) { d in Text("\(d.name) · \(d.inputChannels) in").tag(String?.some(d.uid)) }
                    }
                    .frame(width: 330)
                    .onChange(of: store.inputDeviceUID) { _ in store.restartCapture() }
                    Stepper(String(format: loc.t("assist.firstInput"), store.firstInput), value: $store.firstInput, in: 1...64)
                    Stepper(store.micInput == 0 ? loc.t("assist.noMic") : String(format: loc.t("assist.micInput"), store.micInput),
                            value: $store.micInput, in: 0...64)
                }
                .font(.system(size: 12))
                Text(loc.t("assist.audioHint")).font(.system(size: 11)).foregroundStyle(Theme.textMuted)
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
            Text(String(format: "%.1f", s.gainDB)).monospacedDigit().frame(width: 56, alignment: .trailing)
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
        case let .done(dev): return String(format: loc.t("assist.note.done"), dev)
        case let .gaveUp(r): return loc.t(r == "no signal" ? "assist.note.noSignal" : "assist.note.unsettled")
        }
    }

    private func color(_ n: AssistNote) -> Color {
        switch n {
        case .done: return Theme.statusGood
        case .feedback, .clipRisk, .gaveUp: return Theme.statusWarning
        default: return Theme.textPrimary
        }
    }
}
