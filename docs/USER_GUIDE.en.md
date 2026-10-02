# SSMT — user guide

SSMT sets up a sound system for you: it aligns the subwoofers with the mains (delay, polarity, level) and
suggests EQ over the listening area. Every check is shown as a **tuner instrument**: the needle and LEDs go
from red (far from target) to green ("IN TUNE").

## You need

- A Mac (macOS 13+), an audio interface and a **measurement** microphone (ideally with a calibration file).
- Interface output → processor input. No loopback cable: the generated signal is the reference.
- Access to the loudspeaker processor to mute groups and enter delay, polarity, level and EQ.

## Safety

- The noise starts quietly, rises at most 3 dB/s and never above the "Maximum level".
- **STOP** (red button, **Esc** anywhere, mini window button) mutes the output immediately.
- Captures with clipping are rejected.

## Setup wizard

**0. Prepare.** Choose the interface, microphone input and output (or "Simulation" to try). Put the mic at the
main listening position. Checklist: Start audio → Auto level (5 s of silence, then a slow rise to SNR ≥ 20 dB)
→ Find delay (all loudspeakers on). Describe the system (subs, crossover if known, processor steps). Start setup.

**1. Satellites.** Mute the subs, leave the satellites on → Capture. This capture is stored as the reference.

**2. Phase match (live).** Mute the satellites, leave only the subs. Several times a second SSMT compares the live
sub with the stored satellites using the full alignment (phase match over the overlap band, the correct cycle
checked against the arrival time, polarity, level). Large: what to do now ("Add 3.21 ms to the subs", "Invert the
sub polarity first"), the remaining delay in ms and the phase gap; next to it the phase curves "Satellites (stored)"
and "Subs (live)" — glued, they lie on top of each other; the needles below. Turn the sub delay until all is green →
"Glued — capture the subs". If the subs arrive later than the satellites, the delay goes to the satellites
("Entered … ms on the satellites").

**3. If a correction remains after the capture**, the "phase match" screen with the card and whole-system needles;
otherwise straight to the verification.

**5. Verify.** All loudspeakers on → Capture. "Crossover dip" (green < 3 dB) and "Matches prediction"; if not,
a concrete hint ("looks like the polarity was not changed").

**6. Zone.** Pick a target curve (Flat, Live/PA, Speech, Club or your own via the editor). Measure the points
shown on the map (5 by default).

**7. EQ by the needles.** Leave the mic at point 1, start the EQ tuner (6 s reference), enter the bands one by
one: band needle ("Cut 3 dB more"), overall "EQ vs plan" needle, plan/entered curves. Narrow dips and areas with
large spread between points are deliberately not corrected.

**8. EQ check** over the same points: deviation from target and quality score (a guide, not a guarantee).
At most two correction rounds in a row.

**Done.** Settings, scores, filter export (text/CSV), **PDF/PNG report**, session save (⌘S).

## Microphone correction

Choose your microphone in the list (Prepare step or "Audio and calibration"); its response is removed from the measurement.

- **Your calibration files** — "Import calibration file…" ("frequency dB [phase]", "Sens Factor" headers accepted). Most accurate.
- **Built-in typical profiles** (22 models: measurement mics, Shure SM81, Soyuz 011/013 FET, Soyuz 022 Bomblet, AKG C414 XLII/XLS, Neumann KM 184 / U 87 Ai, RØDE, Oktava MK-012, SM57/SM58 and more) — the model's response from published charts, ±2–3 dB, mostly at high frequencies.
- Cardioid studio microphones read the top end lower in a room than on axis; an omni measurement mic gives a more honest EQ. Any of them is fine for sub/mains alignment.

## Shortcuts

Esc STOP · Space noise · Return capture · ⌘D find delay · ⌘B start setup · ⌘1 wizard · ⌘E expert ·
⌘L stage · ⇧⌘M mini window · ⌘S/⌘O session · ⇧⌘P PDF report.
