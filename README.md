# SSMT — SoundSolution Multi Tool

Native macOS app (13+, Apple Silicon + Intel) for sound engineers. Feature #1: guided automatic
system setup — subwoofer ↔ mains alignment and EQ suggestions from dual-channel FFT measurements.

- Plan: [`docs/PLAN.md`](docs/PLAN.md) · Assumptions: [`docs/ASSUMPTIONS.md`](docs/ASSUMPTIONS.md)
- Status: [`docs/STATUS.md`](docs/STATUS.md)

## Layout

| Path | What |
|---|---|
| `Packages/SSMTCore` | DSP, measurement engine, simulation (no UI, no Core Audio). Fully tested on macOS and Linux. |
| `Packages/SSMTCore/Sources/SSMTRealtime` | C11 lock-free ring buffer and atomics for the audio thread |
| `Packages/SSMTAudio` | Core Audio HAL (AUHAL) duplex backend, device catalog |
| `App/SSMT` | SwiftUI app |
| `project.yml` | XcodeGen project spec |

## Build

```sh
brew install xcodegen      # free, build-time only
xcodegen generate
open SSMT.xcodeproj         # or: xcodebuild -scheme SSMT -configuration Release build
```

Core tests: `swift test -c release --package-path Packages/SSMTCore`
(on Linux without a toolchain: `scripts/linux-swift.sh swift test -c release --package-path Packages/SSMTCore`).

UI strings live in `scripts/strings.py` (en + ru); run `python3 scripts/strings.py generate` after editing.
