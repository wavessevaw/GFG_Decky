import SSMTCore
import SwiftUI

struct MeterPanel: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var loc: Localizer

    var body: some View {
        let s = model.snapshot
        Panel(title: loc.t("meters.title"), marking: "IN-03") {
            MeterBar(label: loc.t("meters.mic"), rmsDBFS: s?.microphone.rmsDBFS ?? -120,
                     peakDBFS: s?.microphone.peakDBFS ?? -120, clipped: s?.microphone.clipped ?? false,
                     clipText: loc.t("meters.clip"))
            if model.referenceMode != .internalSignal {
                MeterBar(label: loc.t("meters.ref"), rmsDBFS: s?.referenceInput.rmsDBFS ?? -120,
                         peakDBFS: s?.referenceInput.peakDBFS ?? -120, clipped: s?.referenceInput.clipped ?? false,
                         clipText: loc.t("meters.clip"))
            }
            TechDivider()
            HStack(spacing: 16) {
                stat(loc.t("meters.coherence"), value: medianCoherence.map { String(format: "%.2f", $0) } ?? "—")
                stat(loc.t("meters.averages"), value: s?.transfer.map { "\($0.averages)" } ?? "—")
                stat(loc.t("meters.delay"), value: s.map { String(format: "%.2f ms", $0.referenceDelaySeconds * 1000) } ?? "—")
                Spacer()
                coherenceBadge
            }
        }
    }

    private var medianCoherence: Double? {
        guard let tf = model.snapshot?.transfer else { return nil }
        let v = tf.frequencies.indices.filter { tf.frequencies[$0] >= 40 && tf.frequencies[$0] <= 16000 && tf.coherence[$0].isFinite }
            .map { tf.coherence[$0] }.sorted()
        return v.isEmpty ? nil : v[v.count / 2]
    }

    @ViewBuilder private var coherenceBadge: some View {
        if let c = medianCoherence {
            if c >= 0.8 {
                StatusBadge(level: .good, text: loc.t("quality.good"))
            } else if c >= model.coherenceThreshold {
                StatusBadge(level: .warning, text: loc.t("quality.weak"))
            } else {
                StatusBadge(level: .error, text: loc.t("quality.repeat"))
            }
        } else {
            StatusBadge(level: .idle, text: loc.t("quality.none"))
        }
    }

    private func stat(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title.uppercased()).font(Theme.label(9)).tracking(1).foregroundStyle(Theme.textMuted)
            Text(value).font(Theme.mono(14, weight: .semibold)).foregroundStyle(Theme.textPrimary)
        }
    }
}
