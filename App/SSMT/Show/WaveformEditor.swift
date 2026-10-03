import SSMTCore
import SwiftUI

/// Waveform editor of an audio cue: drag the start / end flags, the fade handles and the loop
/// edges; click to listen from that point; zoom and pan. One undo step per drag.
struct WaveformEditor: View {
    @EnvironmentObject var show: ShowStore
    @EnvironmentObject var loc: Localizer
    var cue: Cue
    var compact: Bool

    /// Visible window in file seconds (nil span = whole file).
    @State private var viewStart: Double = 0
    @State private var viewSpan: Double?
    @State private var detail: [Float]?
    @State private var detailKey = ""
    @State private var dragHandle: Handle?
    @State private var draft: AudioCueParams?
    @State private var panOrigin: Double?
    @State private var showFull = false

    enum Handle { case start, end, fadeIn, fadeOut, loopStart, loopEnd, pan }

    private var path: String? { show.resolvedPath(cue) }
    private var length: Double? { show.fileLength(cue) }
    private var params: AudioCueParams { draft ?? cue.audio ?? AudioCueParams() }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let length, length > 0 {
                canvas(length: length)
                    .frame(height: compact ? 120 : 280)
                transport(length: length)
                fields(length: length)
                loopControls(length: length)
            } else {
                Text(loc.t(path.map { show.missingFiles.contains($0) } == true ? "show.fileMissing" : "show.wave.loading"))
                    .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            }
        }
        .sheet(isPresented: $showFull) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text([cue.number, cue.name].filter { !$0.isEmpty }.joined(separator: " · ")).font(Theme.heading(17))
                    Spacer()
                    Button(loc.t("settings.done")) { showFull = false }.buttonStyle(SSMTButtonStyle(kind: .primary))
                }
                WaveformEditor(cue: show.doc.cue(cue.id) ?? cue, compact: false)
            }
            .padding(20)
            .frame(width: 1100)
            .background(Backdrop())
            .environmentObject(show)
            .environmentObject(loc)
            .preferredColorScheme(.dark)
        }
    }

    // MARK: Canvas

    private func window(_ length: Double) -> (Double, Double) {
        let span = min(length, max(0.05, viewSpan ?? length))
        let start = min(max(0, viewStart), max(0, length - span))
        return (start, span)
    }

    private func canvas(length: Double) -> some View {
        GeometryReader { geo in
            let (v0, span) = window(length)
            let pps = Double(geo.size.width) / span
            let x = { (t: Double) -> CGFloat in CGFloat((t - v0) * pps) }
            let t = { (x: CGFloat) -> Double in v0 + Double(x) / pps }
            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in draw(&ctx, size: size, length: length, v0: v0, span: span) }
                if let a = show.audition, a.cue == cue.id {
                    TimelineView(.animation) { tl in
                        let pos = a.from + tl.date.timeIntervalSince(a.startedAt) * a.rate
                        Rectangle().fill(Theme.textPrimary).frame(width: 2)
                            .offset(x: x(min(pos, a.from + a.length)))
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        if dragHandle == nil {
                            dragHandle = handle(at: g.startLocation, x: x, height: geo.size.height)
                            draft = cue.audio
                            panOrigin = v0
                        }
                        apply(dragHandle, time: t(g.location.x), dx: g.translation.width, pps: pps, length: length)
                    }
                    .onEnded { g in
                        if abs(g.translation.width) < 3 && abs(g.translation.height) < 3 {
                            // A click: listen from here.
                            show.audition(cue, from: max(0, min(length, t(g.location.x))))
                        } else if dragHandle != .pan, let d = draft {
                            show.updateCue(cue.id) { $0.audio = d }
                        }
                        dragHandle = nil
                        draft = nil
                        panOrigin = nil
                    }
            )
            .task(id: "\(path ?? "")|\(v0)|\(span)|\(Int(geo.size.width))") {
                guard let path else { return }
                let key = "\(path)|\(v0)|\(span)|\(Int(geo.size.width))"
                if let d = await show.waveSlice(path: path, from: v0, to: v0 + span, buckets: max(50, Int(geo.size.width / 2))) {
                    detail = d
                    detailKey = key
                }
            }
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.3)))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    /// Which handle a drag starting at `p` grabs. Fade handles live in the top strip.
    private func handle(at p: CGPoint, x: (Double) -> CGFloat, height: CGFloat) -> Handle {
        let a = params
        let len = length ?? 0
        let s = a.start, e = a.end ?? len
        var candidates: [(Handle, CGFloat)] = []
        if p.y < 24 {
            candidates += [(.fadeIn, x(s + a.fadeIn)), (.fadeOut, x(e - a.fadeOut))]
        }
        if let ls = a.loopStart, let le = a.loopEnd, p.y > height - 26 {
            candidates += [(.loopStart, x(ls)), (.loopEnd, x(le))]
        }
        candidates += [(.start, x(s)), (.end, x(e))]
        let best = candidates.min { abs($0.1 - p.x) < abs($1.1 - p.x) }
        if let best, abs(best.1 - p.x) <= 12 { return best.0 }
        return .pan
    }

    private func apply(_ h: Handle?, time: Double, dx: CGFloat, pps: Double, length: Double) {
        guard var a = draft ?? cue.audio else { return }
        let t = (max(0, min(length, time)) * 1000).rounded() / 1000
        let e = a.end ?? length
        switch h {
        case .start?: a.start = min(t, e - 0.01)
        case .end?: a.end = t >= length - 0.001 ? nil : max(t, a.start + 0.01)
        case .fadeIn?: a.fadeIn = max(0, min(t - a.start, e - a.start))
        case .fadeOut?: a.fadeOut = max(0, min(e - t, e - a.start))
        case .loopStart?: if let le = a.loopEnd { a.loopStart = max(a.start, min(t, le - 0.01)) }
        case .loopEnd?: if let ls = a.loopStart { a.loopEnd = min(e, max(t, ls + 0.01)) }
        case .pan?:
            if let o = panOrigin, viewSpan != nil { viewStart = max(0, o - Double(dx) / pps) }
            return
        case nil: return
        }
        draft = a
    }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize, length: Double, v0: Double, span: Double) {
        let a = params
        let pps = Double(size.width) / span
        func x(_ t: Double) -> CGFloat { CGFloat((t - v0) * pps) }
        let s = a.start, e = a.end ?? length
        let mid = size.height / 2
        let half = size.height * 0.42

        // Waveform: detailed slice when ready, otherwise the file overview.
        var p = Path()
        let cols = max(1, Int(size.width / 2))
        let overview = path.flatMap { show.waveforms[$0] } ?? []
        for k in 0..<cols {
            let px = CGFloat(k) * 2
            var v: Float = 0
            if let d = detail, !d.isEmpty, detailKey.hasSuffix("|\(Int(size.width))") {
                v = d[min(d.count - 1, k * d.count / cols)]
            } else if !overview.isEmpty {
                let tt = v0 + Double(px) / pps
                v = overview[min(overview.count - 1, max(0, Int(tt / length * Double(overview.count))))]
            }
            let h = CGFloat(v) * half
            p.move(to: CGPoint(x: px, y: mid - h)); p.addLine(to: CGPoint(x: px, y: mid + max(0.5, h)))
        }
        ctx.stroke(p, with: .color(Theme.accent.opacity(0.8)), lineWidth: 1)

        // Outside the region: dimmed.
        ctx.fill(Path(CGRect(x: 0, y: 0, width: max(0, x(s)), height: size.height)), with: .color(Color.black.opacity(0.55)))
        ctx.fill(Path(CGRect(x: x(e), y: 0, width: max(0, size.width - x(e)), height: size.height)), with: .color(Color.black.opacity(0.55)))

        // Inner loop.
        if let ls = a.loopStart, let le = a.loopEnd {
            let r = CGRect(x: x(ls), y: 0, width: max(1, x(le) - x(ls)), height: size.height)
            ctx.fill(Path(r), with: .color(Theme.dataBlue.opacity(0.12)))
            ctx.fill(Path(CGRect(x: r.minX, y: size.height - 18, width: r.width, height: 18)), with: .color(Theme.dataBlue.opacity(0.35)))
            for lx in [r.minX, r.maxX] {
                var l = Path(); l.move(to: CGPoint(x: lx, y: 0)); l.addLine(to: CGPoint(x: lx, y: size.height))
                ctx.stroke(l, with: .color(Theme.dataBlue), lineWidth: 1.5)
            }
            let label = a.plays == 0 ? "∞" : "×\(a.plays)"
            ctx.draw(Text(loc.t("show.wave.loop") + " " + label).font(.system(size: 10, weight: .semibold)).foregroundColor(Theme.textPrimary),
                     at: CGPoint(x: r.midX, y: size.height - 9))
        }

        // Fades: the gain curve over the waveform, handles in the top strip.
        var curve = Path()
        curve.move(to: CGPoint(x: x(s), y: size.height))
        curve.addLine(to: CGPoint(x: x(s + a.fadeIn), y: 8))
        curve.addLine(to: CGPoint(x: x(e - a.fadeOut), y: 8))
        curve.addLine(to: CGPoint(x: x(e), y: size.height))
        ctx.stroke(curve, with: .color(Theme.signalYellow.opacity(0.85)), lineWidth: 1.3)
        for hx in [x(s + a.fadeIn), x(e - a.fadeOut)] {
            ctx.fill(Path(ellipseIn: CGRect(x: hx - 5, y: 3, width: 10, height: 10)), with: .color(Theme.signalYellow))
        }

        // Start / end flags.
        for (fx, isStart) in [(x(s), true), (x(e), false)] {
            var l = Path(); l.move(to: CGPoint(x: fx, y: 0)); l.addLine(to: CGPoint(x: fx, y: size.height))
            ctx.stroke(l, with: .color(Theme.accent), lineWidth: 2)
            var flag = Path()
            let w: CGFloat = isStart ? 12 : -12
            flag.move(to: CGPoint(x: fx, y: size.height - 2)); flag.addLine(to: CGPoint(x: fx + w, y: size.height - 9))
            flag.addLine(to: CGPoint(x: fx, y: size.height - 16)); flag.closeSubpath()
            ctx.fill(flag, with: .color(Theme.accent))
        }

        // Time ticks.
        let steps: [Double] = [0.01, 0.05, 0.1, 0.5, 1, 2, 5, 10, 30, 60, 120]
        let step = steps.first { $0 * pps >= 70 } ?? 300
        var tt = (v0 / step).rounded(.up) * step
        while tt < v0 + span {
            ctx.draw(Text(showTime(tt)).font(.system(size: 9, design: .monospaced)).foregroundColor(Theme.textMuted),
                     at: CGPoint(x: x(tt) + 3, y: 22), anchor: .leading)
            var l = Path(); l.move(to: CGPoint(x: x(tt), y: 16)); l.addLine(to: CGPoint(x: x(tt), y: 28))
            ctx.stroke(l, with: .color(Color.white.opacity(0.15)), lineWidth: 1)
            tt += step
        }
    }

    // MARK: Controls

    private func transport(length: Double) -> some View {
        let a = params
        let playing = show.audition?.cue == cue.id
        let e = a.end ?? length
        return HStack(spacing: 6) {
            Button { playing ? show.stopAudition() : show.audition(cue, from: a.start) } label: {
                Label(loc.t(playing ? "show.wave.stop" : "show.wave.play"), systemImage: playing ? "stop.fill" : "play.fill").fixedSize()
            }
            .buttonStyle(ToolButtonStyle())
            Button { show.audition(cue, from: max(a.start, e - 3)) } label: {
                Label(loc.t("show.wave.end"), systemImage: "forward.end").fixedSize()
            }
            .buttonStyle(ToolButtonStyle())
            .help(loc.t("show.wave.end.help"))
            Button { show.trimSilence(cue.id) } label: { Label(loc.t("show.wave.trim"), systemImage: "scissors").fixedSize() }
                .buttonStyle(ToolButtonStyle())
                .help(loc.t("show.wave.trim.help"))
            Spacer(minLength: 0)
            Button { zoom(0.5, length: length) } label: { Image(systemName: "plus.magnifyingglass") }.buttonStyle(.borderless)
            Button { zoom(2, length: length) } label: { Image(systemName: "minus.magnifyingglass") }.buttonStyle(.borderless)
            if compact {
                Button { showFull = true } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                    .buttonStyle(.borderless).help(loc.t("show.wave.expand"))
            }
        }
        .font(.system(size: 12))
    }

    private func zoom(_ factor: Double, length: Double) {
        let (v0, span) = window(length)
        let center = v0 + span / 2
        let newSpan = min(length, max(0.05, span * factor))
        viewSpan = newSpan >= length ? nil : newSpan
        viewStart = max(0, center - newSpan / 2)
    }

    private func fields(length: Double) -> some View {
        let cols = compact ? 2 : 4
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: cols), alignment: .leading, spacing: 8) {
            number(loc.t("show.start"), get: { $0.start }, set: { $0.start = max(0, $1) })
            number(loc.t("show.wave.endField"), get: { $0.end ?? length }, set: { $0.end = $1 >= length - 0.001 ? nil : max(0, $1) })
            number(loc.t("show.fadeIn"), get: { $0.fadeIn }, set: { $0.fadeIn = max(0, $1) })
            number(loc.t("show.fadeOut"), get: { $0.fadeOut }, set: { $0.fadeOut = max(0, $1) })
        }
    }

    private func loopControls(length: Double) -> some View {
        let a = params
        let mode: Int = a.loopStart != nil ? 2 : (a.plays == 1 ? 0 : 1)
        return VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: Binding(get: { mode }, set: { m in
                show.updateCue(cue.id) { c in
                    guard var p = c.audio else { return }
                    switch m {
                    case 0: p.loopStart = nil; p.loopEnd = nil; p.plays = 1
                    case 1: p.loopStart = nil; p.loopEnd = nil; if p.plays == 1 { p.plays = 0 }
                    default:
                        let s = p.start, e = p.end ?? length
                        p.loopStart = ((s + (e - s) / 3) * 100).rounded() / 100
                        p.loopEnd = ((s + 2 * (e - s) / 3) * 100).rounded() / 100
                        if p.plays == 1 { p.plays = 0 }
                    }
                    c.audio = p
                }
            })) {
                Text(loc.t("show.wave.noLoop")).tag(0)
                Text(loc.t("show.wave.loopAll")).tag(1)
                Text(loc.t("show.wave.loopPart")).tag(2)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if mode != 0 {
                HStack(spacing: 8) {
                    Toggle("∞", isOn: Binding(get: { a.plays == 0 }, set: { v in show.updateCue(cue.id) { $0.audio?.plays = v ? 0 : 2 } }))
                        .toggleStyle(.button)
                    if a.plays != 0 {
                        Stepper(String(format: loc.t("show.wave.times"), a.plays),
                                value: Binding(get: { a.plays }, set: { v in show.updateCue(cue.id) { $0.audio?.plays = max(1, v) } }), in: 1...999)
                    }
                    Spacer()
                }
                if mode == 2 {
                    HStack(spacing: 8) {
                        number(loc.t("show.wave.loopStart"), get: { $0.loopStart ?? 0 }, set: { $0.loopStart = max($0.start, $1) })
                        number(loc.t("show.wave.loopEnd"), get: { $0.loopEnd ?? 0 }, set: { $0.loopEnd = $1 })
                    }
                    Text(loc.t("show.wave.loopPart.hint")).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .font(.system(size: 12))
    }

    private func number(_ title: String, get: @escaping (AudioCueParams) -> Double,
                        set: @escaping (inout AudioCueParams, Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title + ", " + loc.t("show.sec")).font(.system(size: 11)).foregroundStyle(Theme.textSecondary).lineLimit(1)
            TextField("", value: Binding(get: { get(params) }, set: { v in
                show.updateCue(cue.id) { c in if var p = c.audio { set(&p, v); c.audio = p } }
            }), format: .number.precision(.fractionLength(0...3)))
            .textFieldStyle(.roundedBorder)
        }
    }
}
