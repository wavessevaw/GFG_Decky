import SSMTCore
import SwiftUI

/// Right column: every setting of the selected cue.
struct CueInspector: View {
    @EnvironmentObject var show: ShowStore
    @EnvironmentObject var loc: Localizer

    var body: some View {
        Group {
            if show.selection.count == 1, let id = show.selection.first, let cue = show.doc.cue(id) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        CueInspectorContent(cue: cue)
                    }
                    .padding(.bottom, 12)
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 26)).foregroundStyle(Theme.textMuted)
                    Text(show.selection.count > 1 ? String(format: loc.t("show.inspector.many"), show.selection.count) : loc.t("show.inspector.none"))
                        .font(.system(size: 12)).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .glassCard(padding: 16)
            }
        }
    }
}

private struct CueInspectorContent: View {
    @EnvironmentObject var show: ShowStore
    @EnvironmentObject var loc: Localizer
    var cue: Cue

    var body: some View {
        section(loc.t("cue.kind.\(cue.kind.rawValue)"), icon: cue.kind.icon) {
            HStack(spacing: 8) {
                field(loc.t("show.col.number"), text: bind(\.number)).frame(width: 70)
                field(loc.t("show.col.name"), text: bind(\.name))
            }
            VStack(alignment: .leading, spacing: 4) {
                caption(loc.t("show.notes"))
                TextEditor(text: bind(\.notes))
                    .font(.system(size: 12))
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .frame(height: 54)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.25)))
            }
            HStack(spacing: 6) {
                ForEach(CueColor.allCases, id: \.rawValue) { c in
                    Button { show.updateCue(cue.id) { $0.color = c.rawValue } } label: {
                        Circle().fill(c == .none ? Color.white.opacity(0.08) : c.color)
                            .frame(width: 16, height: 16)
                            .overlay(Circle().strokeBorder(Color.white.opacity(cue.color == c.rawValue ? 0.9 : 0.15), lineWidth: cue.color == c.rawValue ? 2 : 1))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Toggle(loc.t("show.armed"), isOn: bind(\.armed)).toggleStyle(.switch).controlSize(.mini)
            }
        }

        section(loc.t("show.timing"), icon: "timer") {
            HStack(spacing: 8) {
                seconds(loc.t("show.col.pre"), bind(\.preWait))
                seconds(loc.t("show.col.post"), bind(\.postWait)).disabled(cue.continueMode != .autoContinue)
            }
            VStack(alignment: .leading, spacing: 4) {
                caption(loc.t("show.continue"))
                Picker("", selection: bind(\.continueMode)) {
                    ForEach(ContinueMode.allCases, id: \.self) { Text(loc.t("continue.\($0.rawValue)")).tag($0) }
                }
                .labelsHidden()
            }
            HStack {
                caption(loc.t("show.hotkey"))
                Spacer()
                TextField("—", text: Binding(get: { cue.hotkey ?? "" }, set: { v in
                    let key = v.trimmingCharacters(in: .whitespaces).suffix(1)
                    show.updateCue(cue.id) { $0.hotkey = key.isEmpty ? nil : String(key) }
                }))
                .textFieldStyle(.roundedBorder).frame(width: 44).multilineTextAlignment(.center)
            }
        }

        switch cue.kind {
        case .audio: audioSection
        case .fade: fadeSection
        case .group: groupSection
        case .wait:
            section(loc.t("cue.kind.wait"), icon: "hourglass") { seconds(loc.t("show.duration"), bind(\.duration)) }
        case .memo: EmptyView()
        default: controlSection
        }
    }

    // MARK: Audio

    private var path: String? { show.resolvedPath(cue) }
    private var info: (duration: Double, channels: Int)? { path.flatMap { show.clipInfo[$0] } }

    @ViewBuilder private var audioSection: some View {
        section(loc.t("show.file"), icon: "doc.waveform") {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(cue.audio.map { ($0.file as NSString).lastPathComponent } ?? "—")
                        .font(.system(size: 12, weight: .medium)).lineLimit(2)
                    if let info {
                        Text("\(showTime(info.duration)) · \(info.channels) ch").font(Theme.mono(11)).foregroundStyle(Theme.textSecondary)
                    } else if let p = path, show.missingFiles.contains(p) {
                        Text(loc.t("show.fileMissing")).font(.system(size: 11)).foregroundStyle(Theme.statusWarning)
                    }
                }
                Spacer()
                Button(loc.t("show.chooseFile")) { show.chooseFile(for: cue.id) }.buttonStyle(SSMTButtonStyle())
            }
            HStack(spacing: 8) {
                seconds(loc.t("show.start"), audio(\.start, 0))
                VStack(alignment: .leading, spacing: 4) {
                    caption(loc.t("show.end"))
                    TextField(info.map { showTime($0.duration) } ?? "—", value: Binding(
                        get: { cue.audio?.end }, set: { v in show.updateCue(cue.id) { $0.audio?.end = v.map { max(0, $0) } } }),
                              format: .number.precision(.fractionLength(0...2)))
                        .textFieldStyle(.roundedBorder)
                }
            }
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    caption(loc.t("show.plays"))
                    HStack(spacing: 6) {
                        Toggle("∞", isOn: Binding(get: { cue.audio?.plays == 0 }, set: { v in
                            show.updateCue(cue.id) { $0.audio?.plays = v ? 0 : 1 }
                        }))
                        .toggleStyle(.button)
                        if cue.audio?.plays != 0 {
                            Stepper("\(cue.audio?.plays ?? 1)", value: audio(\.plays, 1), in: 1...999)
                        }
                    }
                }
                Spacer()
                VStack(alignment: .leading, spacing: 4) {
                    caption(loc.t("show.rate"))
                    TextField("", value: audio(\.rate, 1), format: .number.precision(.fractionLength(0...3)))
                        .textFieldStyle(.roundedBorder).frame(width: 70)
                }
            }
            level(loc.t("show.level"), audio(\.level, 0))
            HStack(spacing: 8) {
                seconds(loc.t("show.fadeIn"), audio(\.fadeIn, 0))
                seconds(loc.t("show.fadeOut"), audio(\.fadeOut, 0))
            }
        }
        section(loc.t("show.routing"), icon: "point.3.connected.trianglepath.dotted") { routingGrid }
    }

    /// Crosspoints: file channels (rows) × show outputs (columns); click to connect.
    private var routingGrid: some View {
        let channels = max(1, info?.channels ?? 2)
        let outs = show.doc.outputs
        return ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text("").frame(width: 28)
                    ForEach(Array(outs.enumerated()), id: \.offset) { _, o in
                        Text(o.name).font(.system(size: 9)).foregroundStyle(Theme.textSecondary).frame(width: 24).lineLimit(1)
                    }
                }
                ForEach(0..<channels, id: \.self) { c in
                    HStack(spacing: 4) {
                        Text(channels == 2 ? (c == 0 ? "L" : "R") : "\(c + 1)")
                            .font(Theme.mono(11)).foregroundStyle(Theme.textSecondary).frame(width: 28)
                        ForEach(0..<outs.count, id: \.self) { o in
                            let on = (cue.audio?.crosspoint(channel: c, output: o, fileChannels: channels) ?? showSilenceDB) > showSilenceDB
                            Button { toggle(channel: c, output: o, channels: channels, outputs: outs.count) } label: {
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(on ? Theme.accent : Color.white.opacity(0.07))
                                    .frame(width: 24, height: 22)
                                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.white.opacity(0.1)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func toggle(channel c: Int, output o: Int, channels: Int, outputs: Int) {
        show.updateCue(cue.id) { cue in
            guard var a = cue.audio else { return }
            if a.routing.count < channels {
                // Materialise the default routing before the first manual change.
                a.routing = (0..<channels).map { ch in (0..<outputs).map { a.crosspoint(channel: ch, output: $0, fileChannels: channels) } }
            }
            while a.routing[c].count < outputs { a.routing[c].append(showSilenceDB) }
            a.routing[c][o] = a.routing[c][o] > showSilenceDB ? showSilenceDB : 0
            cue.audio = a
        }
    }

    // MARK: Fade

    @ViewBuilder private var fadeSection: some View {
        section(loc.t("cue.kind.fade"), icon: cue.kind.icon) {
            targetPicker(loc.t("show.target"), \.target)
            HStack(spacing: 8) {
                seconds(loc.t("show.duration"), fade(\.duration, 3))
                VStack(alignment: .leading, spacing: 4) {
                    caption(loc.t("show.curve"))
                    Picker("", selection: fade(\.curve, .sCurve)) {
                        ForEach(FadeCurve.allCases, id: \.self) { Text(loc.t("curve.\($0.rawValue)")).tag($0) }
                    }
                    .labelsHidden()
                }
            }
            Toggle(loc.t("show.fade.changeLevel"), isOn: Binding(get: { cue.fade?.level != nil }, set: { v in
                show.updateCue(cue.id) { $0.fade?.level = v ? showSilenceDB : nil }
            }))
            if cue.fade?.level != nil {
                level(loc.t("show.fade.to"), Binding(get: { cue.fade?.level ?? showSilenceDB },
                                                     set: { v in show.updateCue(cue.id) { $0.fade?.level = v } }))
            }
            Toggle(loc.t("show.fade.stop"), isOn: fade(\.stopWhenDone, true))
        }
    }

    // MARK: Group

    @ViewBuilder private var groupSection: some View {
        section(loc.t("cue.kind.group"), icon: cue.kind.icon) {
            Picker("", selection: bind(\.groupMode)) {
                ForEach(GroupMode.allCases, id: \.self) { Text(loc.t("group.mode.\($0.rawValue)")).tag($0) }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            if cue.groupMode == .playlist {
                Toggle(loc.t("show.playlist.loop"), isOn: bind(\.loopPlaylist))
                Toggle(loc.t("show.playlist.shuffle"), isOn: bind(\.shuffle))
            }
            Text(String(format: loc.t("show.group.count"), cue.children.count))
                .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: Control cues

    @ViewBuilder private var controlSection: some View {
        section(loc.t("cue.kind.\(cue.kind.rawValue)"), icon: cue.kind.icon) {
            targetPicker(loc.t("show.target"), \.target, allowsAll: cue.kind == .stop)
            switch cue.kind {
            case .stop: seconds(loc.t("show.stopFade"), bind(\.stopFade))
            case .target: targetPicker(loc.t("show.newTarget"), \.newTarget)
            case .devamp: Toggle(loc.t("show.devamp.next"), isOn: bind(\.devampStartsNext))
            default: EmptyView()
            }
            Text(loc.t("cue.help.\(cue.kind.rawValue)")).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func targetPicker(_ title: String, _ key: WritableKeyPath<Cue, UUID?>, allowsAll: Bool = false) -> some View {
        let candidates = key == \Cue.newTarget ? show.doc.allCues.filter { $0.id != cue.id }
            : show.doc.targetCandidates(for: cue.kind, excluding: cue.id)
        let current = show.doc.cue(cue[keyPath: key])
        return VStack(alignment: .leading, spacing: 4) {
            caption(title)
            Menu {
                if allowsAll { Button(loc.t("show.target.all")) { show.updateCue(cue.id) { $0[keyPath: key] = nil } } }
                ForEach(candidates) { c in
                    Button(label(c)) { show.updateCue(cue.id) { $0[keyPath: key] = c.id } }
                }
            } label: {
                Text(current.map(label) ?? (allowsAll ? loc.t("show.target.all") : loc.t("show.noTarget")))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func label(_ c: Cue) -> String {
        [c.number, c.name.isEmpty ? loc.t("cue.kind.\(c.kind.rawValue)") : c.name].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    // MARK: Building blocks

    private func section<C: View>(_ title: String, icon: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 12)).foregroundStyle(Theme.accent)
                Text(title).font(.system(size: 13, weight: .semibold))
            }
            content()
        }
        .font(.system(size: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(padding: 14)
    }

    private func caption(_ t: String) -> some View {
        Text(t).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            caption(title)
            TextField("", text: text).textFieldStyle(.roundedBorder)
        }
    }

    private func seconds(_ title: String, _ value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            caption(title + ", " + loc.t("show.sec"))
            TextField("", value: Binding(get: { value.wrappedValue }, set: { value.wrappedValue = max(0, $0) }),
                      format: .number.precision(.fractionLength(0...2)))
                .textFieldStyle(.roundedBorder)
        }
    }

    private func level(_ title: String, _ value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                caption(title)
                Spacer()
                Text(value.wrappedValue <= showSilenceDB ? "−∞ dB" : String(format: "%+.1f dB", value.wrappedValue))
                    .font(Theme.mono(11))
            }
            Slider(value: Binding(get: { max(-60, value.wrappedValue) },
                                  set: { v in value.wrappedValue = v <= -60 ? showSilenceDB : (v * 2).rounded() / 2 }),
                   in: -60...12)
        }
    }

    private func bind<T>(_ key: WritableKeyPath<Cue, T>) -> Binding<T> {
        let id = cue.id
        let fallback = cue[keyPath: key]
        return Binding(get: { show.doc.cue(id)?[keyPath: key] ?? fallback },
                       set: { v in show.updateCue(id) { $0[keyPath: key] = v } })
    }

    private func audio<T>(_ key: WritableKeyPath<AudioCueParams, T>, _ fallback: T) -> Binding<T> {
        let id = cue.id
        return Binding(get: { show.doc.cue(id)?.audio?[keyPath: key] ?? fallback },
                       set: { v in show.updateCue(id) { $0.audio?[keyPath: key] = v } })
    }

    private func fade<T>(_ key: WritableKeyPath<FadeCueParams, T>, _ fallback: T) -> Binding<T> {
        let id = cue.id
        return Binding(get: { show.doc.cue(id)?.fade?[keyPath: key] ?? fallback },
                       set: { v in show.updateCue(id) { $0.fade?[keyPath: key] = v } })
    }
}
