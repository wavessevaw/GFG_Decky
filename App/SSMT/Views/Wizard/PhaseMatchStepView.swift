import SSMTCore
import SwiftUI

/// Subwoofer step — live phase match. The satellites were captured and are the fixed reference;
/// only the subwoofers play. The user turns the sub delay (polarity, level) on the processor while
/// the needle — the full alignment of the live sub against the stored satellites, several times a
/// second — shows what is left, and the two phase curves close up. When glued, the sub is captured.
struct PhaseMatchStepView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var loc: Localizer

    var body: some View {
        StepScaffold(title: loc.t("match.step.title"), subtitle: loc.t("match.step.subtitle"), info: loc.t("match.step.info")) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    groupPill(loc.t("group.mains"), on: false)
                    groupPill(loc.t("group.subs"), on: true)
                }
                HStack(alignment: .top, spacing: 16) {
                    LiveMatchHeadline()
                    LivePhaseOverlay()
                }
                LateSubsNotice()
                TunerPanel()
                if model.wizardCaptureRunning { CaptureProgressBar() }
                if let acc = model.lastAcceptance, case .rejected(let reasons) = acc {
                    Text(loc.t("capture.rejected") + " " + reasons.map { loc.t("reason.\($0.rawValue)") }.joined(separator: " "))
                        .font(.system(size: 13)).foregroundStyle(Theme.statusError)
                }
                if model.isSimulation {
                    HStack(spacing: 16) {
                        QuietButton(title: loc.t("sim.phaseMatch"), icon: "wand.and.stars") { model.simulateApplyPhaseMatch() }
                    }
                    Collapsible(title: loc.t("vproc.title")) { VirtualProcessorPanel() }
                }
            }
        } actions: {
            PhaseMatchActions()
        }
        .onAppear { model.startPhaseMatch() }
        .onDisappear { model.stopTuner() }
    }

    private func groupPill(_ name: String, on: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: on ? "speaker.wave.2.fill" : "speaker.slash.fill")
            Text(name)
            Text(on ? loc.t("group.on") : loc.t("group.muted")).foregroundStyle(on ? Theme.textPrimary : Theme.textMuted)
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(on ? Theme.accent : Theme.textMuted)
        .padding(.horizontal, 16).padding(.vertical, 9)
        .background(Capsule().fill(on ? Theme.accent.opacity(0.14) : Theme.panel))
    }
}

/// The one instruction of the moment ("Add 3.21 ms to the subs") with the remaining delay in large
/// digits and the phase gap.
struct LiveMatchHeadline: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var tuning: TuningData
    @EnvironmentObject var loc: Localizer

    var body: some View {
        let r = tuning.alignment
        let state = instruction(r)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if r?.allInTune == true && r?.isReliable == true { Image(systemName: "checkmark.circle.fill") }
                Text(state.text).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(state.color)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(r.map { String(format: "%+.2f", $0.delayError * 1000) } ?? "—")
                    .font(Theme.numeral(56)).foregroundStyle(r == nil ? Theme.textMuted : Theme.textPrimary)
                Text(loc.t("unit.ms")).font(.system(size: 18)).foregroundStyle(Theme.textSecondary)
            }
            if let r {
                Text(String(format: loc.t("match.phase.gap"), r.phaseGapDegrees))
                    .font(Theme.mono(13))
                    .foregroundStyle(Theme.closeness(max(0, 1 - (r.phaseGapDegrees - 15) / 75)))
                Text(String(format: "XO %.0f Hz", r.crossover)).font(Theme.mono(12)).foregroundStyle(Theme.textMuted)
            }
        }
        .frame(width: 300, alignment: .leading)
        .glassCard(padding: 20, highlighted: true)
        .animation(.easeOut(duration: 0.2), value: r?.allInTune)
    }

    private func instruction(_ r: AlignmentTuner.Reading?) -> (text: String, color: Color) {
        guard let r else { return (loc.t("tuner.waiting"), Theme.textMuted) }
        guard r.isReliable else { return (loc.t("match.do.weak"), Theme.signalYellow) }
        let ms = abs(r.delayError) * 1000
        let c = Theme.closeness(max(0, 1 - abs(r.delayPhaseError) / 90))
        if r.polarityWrong { return (loc.t("match.do.polarity"), Theme.statusError) }
        if !r.delayInTune {
            return (String(format: loc.t(r.delayError > 0 ? "match.do.addSub" : "match.do.reduceSub"), ms), c)
        }
        if !r.levelInTune { return (String(format: loc.t("match.do.level"), r.levelError), Theme.signalYellow) }
        return (loc.t("match.do.glued"), Theme.statusGood)
    }
}

/// Stored satellites vs the live subwoofer: the curves close up while the sub delay is turned.
struct LivePhaseOverlay: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var live: LiveData
    @EnvironmentObject var tuning: TuningData
    @EnvironmentObject var loc: Localizer

    var body: some View {
        let fc = tuning.alignment?.crossover ?? model.wizard.configuration.crossover ?? 100
        VStack(alignment: .leading, spacing: 12) {
            CardTitle(title: loc.t("match.phase.title"))
            if let mains = model.wizard.mainsResponse, let sub = live.snapshot?.transfer,
               mains.frequencies == sub.frequencies {
                PhaseOverlayPlot(mains: mains, sub: sub, crossover: fc, overlap: (fc / 1.5)...(fc * 1.5),
                                 mainsLabel: loc.t("match.phase.savedMains"), subLabel: loc.t("match.phase.liveSub"))
            } else {
                Text(loc.t("tuner.waiting")).font(.system(size: 13)).foregroundStyle(Theme.textMuted)
                    .frame(maxWidth: .infinity, minHeight: 220)
            }
        }
        .frame(maxWidth: .infinity)
        .glassCard(padding: 18)
    }
}

/// Subs later than the satellites and no sub delay left to remove: the satellites get the delay.
struct LateSubsNotice: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var tuning: TuningData
    @EnvironmentObject var loc: Localizer

    var body: some View {
        if let r = tuning.alignment, r.isReliable, !r.delayInTune, r.delayError < 0 {
            let ms = -r.delayError * 1000
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "clock.arrow.circlepath").font(.system(size: 20)).foregroundStyle(Theme.signalYellow)
                Text(String(format: loc.t("match.lateSubs"), ms))
                    .font(.system(size: 13)).foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button(String(format: loc.t("match.lateSubs.button"), ms)) {
                    model.phaseMatchEnterMainsDelay(seconds: -r.delayError)
                }
                .buttonStyle(SSMTButtonStyle())
            }
            .glassCard(padding: 16)
        }
    }
}

/// "Glued — capture the subs" (also possible before it is fully glued), Back.
struct PhaseMatchActions: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var tuning: TuningData
    @EnvironmentObject var loc: Localizer

    var body: some View {
        let glued = tuning.alignment.map { $0.allInTune && $0.isReliable } ?? false
        ActionRow(primaryTitle: model.wizardCaptureRunning ? loc.t("action.cancel") : loc.t(glued ? "match.lock" : "match.lock.anyway"),
                  primaryIcon: model.wizardCaptureRunning ? "xmark" : (glued ? "lock.fill" : "record.circle"),
                  primaryEnabled: model.isRunning,
                  primaryAction: { model.wizardCaptureRunning ? model.wizardCancelCapture() : model.wizardCapture() }) {
            QuietButton(title: loc.t("wizard.back"), icon: "chevron.left") { model.wizardBack() }
        }
    }
}
