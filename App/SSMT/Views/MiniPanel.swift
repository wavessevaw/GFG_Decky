import AppKit
import SSMTCore
import SwiftUI

/// Floating diagnostics panel. Appears when the main window is minimized (or on demand),
/// stays above all windows, can be dragged, snaps to screen edges, has adjustable opacity
/// and an optional click-through mode. The measurement engine is unaffected by any of this.
@MainActor
final class MiniPanelController: NSObject, NSWindowDelegate {
    static let shared = MiniPanelController()

    weak var model: AppModel?
    weak var localizer: Localizer?
    private var panel: NSPanel?
    private var observers: [NSObjectProtocol] = []

    @AppStorage("ssmt.mini.opacity") var opacity: Double = 0.92 { didSet { panel?.alphaValue = opacity } }
    @AppStorage("ssmt.mini.clickThrough") var clickThrough = false { didSet { panel?.ignoresMouseEvents = clickThrough } }
    @AppStorage("ssmt.mini.autoShow") var autoShowOnMinimize = true

    var isVisible: Bool { panel?.isVisible ?? false }

    func attach(model: AppModel, localizer: Localizer) {
        self.model = model
        self.localizer = localizer
        guard observers.isEmpty else { return }
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: NSWindow.didMiniaturizeNotification, object: nil, queue: .main) { [weak self] n in
            guard !(n.object is NSPanel) else { return }
            Task { @MainActor in if self?.autoShowOnMinimize == true { self?.show() } }
        })
        observers.append(nc.addObserver(forName: NSWindow.didDeminiaturizeNotification, object: nil, queue: .main) { [weak self] n in
            guard !(n.object is NSPanel) else { return }
            Task { @MainActor in self?.hide() }
        })
    }

    func toggle() { isVisible ? hide() : show() }

    func show() {
        guard let model, let localizer else { return }
        if panel == nil {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 330),
                            styleMask: [.borderless, .nonactivatingPanel, .resizable],
                            backing: .buffered, defer: false)
            p.isFloatingPanel = true
            p.level = .floating
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.hidesOnDeactivate = false
            p.isMovableByWindowBackground = true
            p.backgroundColor = .clear
            p.isOpaque = false
            p.hasShadow = true
            p.delegate = self
            p.contentView = NSHostingView(rootView: MiniDiagnosticsView()
                .environmentObject(model).environmentObject(localizer))
            if let screen = NSScreen.main?.visibleFrame {
                p.setFrameOrigin(NSPoint(x: screen.maxX - 400, y: screen.maxY - 350))
            }
            panel = p
        }
        panel?.alphaValue = opacity
        panel?.ignoresMouseEvents = clickThrough
        panel?.orderFrontRegardless()
    }

    func hide() { panel?.orderOut(nil) }

    /// Brings the main window back.
    func expandMainWindow() {
        hide()
        NSApp.activate(ignoringOtherApps: true)
        for w in NSApp.windows where !(w is NSPanel) {
            if w.isMiniaturized { w.deminiaturize(nil) }
            w.makeKeyAndOrderFront(nil)
        }
    }

    // Snap to screen edges when dragged close to them.
    func windowDidMove(_ notification: Notification) {
        snapToEdges()
    }

    private func snapToEdges() {
        guard let p = panel, let screen = p.screen?.visibleFrame else { return }
        var f = p.frame
        let d: CGFloat = 24
        if abs(f.minX - screen.minX) < d { f.origin.x = screen.minX + 4 }
        if abs(f.maxX - screen.maxX) < d { f.origin.x = screen.maxX - f.width - 4 }
        if abs(f.minY - screen.minY) < d { f.origin.y = screen.minY + 4 }
        if abs(f.maxY - screen.maxY) < d { f.origin.y = screen.maxY - f.height - 4 }
        if f.origin != p.frame.origin { p.setFrameOrigin(f.origin) }
    }
}

/// Compact live diagnostics in the instrument style.
struct MiniDiagnosticsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var loc: Localizer
    @State private var settings = false

    var body: some View {
        let s = model.snapshot
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                BrandMark(variant: .compact, height: 16)
                Text(statusLine).font(Theme.label(11)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                Spacer()
                Menu {
                    ForEach([1.0, 0.85, 0.7, 0.55], id: \.self) { o in
                        Button(String(format: "%@ %.0f %%", loc.t("mini.opacity"), o * 100)) { MiniPanelController.shared.opacity = o }
                    }
                    Divider()
                    Button(loc.t("mini.clickThrough")) { MiniPanelController.shared.clickThrough = true }
                } label: { Image(systemName: "gearshape") }
                    .menuStyle(.borderlessButton).frame(width: 26)
                Button { MiniPanelController.shared.expandMainWindow() } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                    .buttonStyle(.plain).help(loc.t("mini.expand"))
            }

            // EQ average (live, 1/3 oct) vs target, with deviation.
            ZStack(alignment: .topTrailing) {
                MiniCurve(transfer: model.displayTransfer, target: model.wizard.configuration.target)
                    .frame(height: 92)
                Text(deviation.map { String(format: "±%.1f dB", $0) } ?? "—")
                    .font(Theme.mono(13)).foregroundStyle(Theme.textPrimary)
                    .padding(8)
            }
            .background(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous).fill(Color.white.opacity(0.04)))

            // SPL
            HStack(spacing: 6) {
                splCell("LAeq", s?.soundLevel.laeq)
                splCell("LCeq", s?.soundLevel.lceq)
                splCell("LCpk", s?.soundLevel.lpeak)
                splCell("LAFmax", s?.soundLevel.lmax)
            }

            // Inputs
            MeterBar(label: loc.t("meters.mic"), rmsDBFS: s?.microphone.rmsDBFS ?? -120,
                     peakDBFS: s?.microphone.peakDBFS ?? -120, clipped: s?.microphone.clipped ?? false,
                     clipText: loc.t("meters.clip"))
            if model.referenceMode != .internalSignal {
                MeterBar(label: loc.t("meters.ref"), rmsDBFS: s?.referenceInput.rmsDBFS ?? -120,
                         peakDBFS: s?.referenceInput.peakDBFS ?? -120, clipped: s?.referenceInput.clipped ?? false,
                         clipText: loc.t("meters.clip"))
            }

            HStack(spacing: 10) {
                IndicatorLamp(color: quality.map { Theme.closeness(($0 - 0.3) / 0.5) } ?? Theme.textMuted, size: 16)
                Text(quality.map { String(format: "%@ %.0f %%", loc.t("gauge.quality"), $0 * 100) } ?? loc.t("quality.none"))
                    .font(Theme.label(12)).foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(delayText).font(Theme.mono(11)).foregroundStyle(Theme.textSecondary)
            }

            HStack {
                Text(loc.t("target.\(model.wizard.configuration.target.preset.rawValue)"))
                    .font(Theme.label(11)).foregroundStyle(Theme.textMuted)
                Spacer()
                Button { model.emergencyStop() } label: {
                    Label(loc.t("action.stop"), systemImage: "stop.fill").font(Theme.heading(13))
                }
                .buttonStyle(SSMTButtonStyle(kind: .danger))
            }
        }
        .padding(14)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(GlassBackground())
        .preferredColorScheme(.dark)
    }

    private var statusLine: String {
        let mode = loc.t(model.appMode == .wizard ? "mode.wizard" : "mode.expert")
        let step = model.appMode == .wizard ? " · " + loc.t("wizard.step.\(model.wizard.step.rawValue)") : ""
        let noise = model.noiseOn ? " · ●" : ""
        return (mode + step + noise)
    }

    private var quality: Double? {
        guard let tf = model.snapshot?.transfer else { return nil }
        let v = tf.frequencies.indices.filter { tf.frequencies[$0] >= 40 && tf.frequencies[$0] <= 16000 && tf.coherence[$0].isFinite }
            .map { tf.coherence[$0] }.sorted()
        return v.isEmpty ? nil : v[v.count / 2]
    }

    /// RMS deviation of the live (1/3-oct) response from the level-aligned target, 63 Hz–12.5 kHz.
    private var deviation: Double? {
        guard let tf = model.displayTransfer else { return nil }
        let sm = Smoothing.smooth(tf, resolution: .oct3)
        let idx = sm.frequencies.indices.filter { sm.frequencies[$0] >= 63 && sm.frequencies[$0] <= 12500 && sm.isValid($0) }
        guard idx.count > 4 else { return nil }
        let d = idx.map { Decibel.fromAmplitude(sm.response[$0].magnitude) - model.wizard.configuration.target.value(at: sm.frequencies[$0]) }
        let m = d.reduce(0, +) / Double(d.count)
        return (d.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(d.count)).squareRoot()
    }

    private var delayText: String {
        if let d = model.delay, d.isReliable { return String(format: "Δt %.2f ms", d.milliseconds) }
        return loc.t("mini.noDelay")
    }

    private func splCell(_ name: String, _ v: Double?) -> some View {
        VStack(spacing: 2) {
            Text(v.map { String(format: "%.0f", $0) } ?? "—").font(Theme.numeral(20)).foregroundStyle(Theme.textPrimary)
            Text(name).font(Theme.label(11)).foregroundStyle(Theme.textMuted)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Tiny magnitude plot: live response (closeness colour) and the target (dashed).
struct MiniCurve: View {
    var transfer: TransferFunction?
    var target: TargetCurve

    var body: some View {
        Canvas { ctx, size in
            let axis = FrequencyAxis()
            guard let tf = transfer else { return }
            let sm = Smoothing.smooth(tf, resolution: .oct3)
            let idx = sm.frequencies.indices.filter { sm.isValid($0) }
            let mids = idx.filter { sm.frequencies[$0] >= 200 && sm.frequencies[$0] <= 4000 }
                .map { Decibel.fromAmplitude(sm.response[$0].magnitude) - target.value(at: sm.frequencies[$0]) }.sorted()
            let ref = mids.isEmpty ? 0 : mids[mids.count / 2]
            func y(_ db: Double) -> CGFloat { size.height / 2 - CGFloat(db - ref) * size.height / 30 }
            var t = Path()
            var first = true
            for f in sm.frequencies {
                let p = CGPoint(x: axis.x(f, width: size.width), y: y(target.value(at: f)))
                if first { t.move(to: p); first = false } else { t.addLine(to: p) }
            }
            ctx.stroke(t, with: .color(.white.opacity(0.3)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            var m = Path()
            first = true
            for i in idx {
                let p = CGPoint(x: axis.x(sm.frequencies[i], width: size.width), y: y(Decibel.fromAmplitude(sm.response[i].magnitude)))
                if first { m.move(to: p); first = false } else { m.addLine(to: p) }
            }
            ctx.stroke(m, with: .color(Theme.accent), lineWidth: 1.6)
        }
    }
}
