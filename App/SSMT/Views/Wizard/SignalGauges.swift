import SSMTCore
import SwiftUI

/// "Signal quality" needle: how stable the measurement is in the band that matters for this step
/// (median coherence, shown as a percentage — the word coherence stays in the Expert view).
struct SignalQualityGauge: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var loc: Localizer
    var band: ClosedRange<Double>

    var body: some View {
        let q = quality
        let clipped = model.snapshot?.microphone.clipped ?? false
        TunerGauge(
            title: loc.t("gauge.quality"),
            value: clipped ? 0 : q.map { ($0 - 0.3) / 0.55 },
            mode: .oneSided,
            tolerance: (0.8 - 0.3) / 0.55,
            readout: clipped ? loc.t("meters.clip") : (q.map { String(format: "%.0f %%", $0 * 100) } ?? "—"),
            instruction: instruction(q, clipped: clipped),
            large: model.stageMode)
    }

    private var quality: Double? {
        guard let tf = model.snapshot?.transfer else { return nil }
        let v = tf.frequencies.indices.filter { band.contains(tf.frequencies[$0]) && tf.coherence[$0].isFinite }
            .map { tf.coherence[$0] }.sorted()
        return v.isEmpty ? nil : v[v.count / 2]
    }

    private func instruction(_ q: Double?, clipped: Bool) -> String {
        if clipped { return loc.t("gauge.quality.clip") }
        guard let q else { return loc.t("tuner.waiting") }
        if q >= 0.8 { return loc.t("gauge.quality.good") }
        if q >= 0.6 { return loc.t("gauge.quality.weak") }
        return loc.t("gauge.quality.bad")
    }
}

/// Live signal-to-noise needle against the measured room noise (target ≥ 20 dB).
struct SNRGauge: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var loc: Localizer

    var body: some View {
        let snr = liveSNR
        TunerGauge(
            title: loc.t("gauge.snr"),
            value: snr.map { $0 / 30 },
            mode: .oneSided,
            tolerance: 20.0 / 30,
            readout: snr.map { String(format: "%.0f dB", $0) } ?? "—",
            instruction: snr.map { loc.t($0 >= 20 ? "gauge.snr.good" : "gauge.snr.low") }
                ?? loc.t(model.noiseFloor == nil ? "gauge.snr.needNoise" : "tuner.waiting"),
            large: model.stageMode)
    }

    private var liveSNR: Double? {
        guard model.noiseOn, let nf = model.noiseFloor, let tf = model.snapshot?.transfer,
              nf.count == tf.measurementPower.count else { return nil }
        let snr = SNREstimator.snr(measurementPower: tf.measurementPower, noiseFloor: nf)
        return SNREstimator.medianSNR(snr, frequencies: tf.frequencies, band: 50...12000)
    }
}
