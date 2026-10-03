<div align="center">

<img src="docs/media/icon.png" width="128" alt="SSMT">

# SSMT — SoundSolution Multi Tool

**Профессиональный инструмент звукоинженера для macOS**<br>
настройка звукоусилительной системы · документация мероприятия · воспроизведение шоу · ассистент микширования

[![Release](https://img.shields.io/github/v/release/wavessevaw/SSMT-Soundsolution-Multitool-?label=release&color=2EE59D)](../../releases/latest)
[![CI](https://github.com/wavessevaw/SSMT-Soundsolution-Multitool-/actions/workflows/ci.yml/badge.svg)](../../actions/workflows/ci.yml)
![macOS](https://img.shields.io/badge/macOS-13%2B-black?logo=apple)
![Apple Silicon | Intel](https://img.shields.io/badge/Apple%20Silicon%20%7C%20Intel-universal-10A86E)
![RU | EN](https://img.shields.io/badge/язык-RU%20%7C%20EN-A7F3D0)

<img src="docs/media/hero.png" alt="SSMT" width="100%">

</div>

> [!NOTE]
> **FOH Assist находится в статусе beta.** Взаимодействие с микшерными пультами Behringer X32 / Midas M32 и
> X Air / Midas MR реализовано на основе открытой спецификации протокола и проходит проверку на оборудовании.
> Перед работой рекомендуется выполнить «Тест пульта»: он проверяет обмен данными и восстанавливает исходные настройки.

## 📥 Загрузка

| Компонент | Назначение | Ссылка |
|---|---|---|
| **SSMT** — установщик `.pkg` | macOS 13 и новее, Apple Silicon и Intel | [**Последний релиз**](../../releases/latest) |
| Руководство пользователя | Описание всех функций и порядка работы | [Русский](docs/USER_GUIDE.ru.md) · [English](docs/USER_GUIDE.en.md) |
| Инструкция по установке | Первый запуск приложения без подписи Apple Developer ID | [docs/INSTALL.md](docs/INSTALL.md) |

## 🎚️ Назначение

Подготовка каждого мероприятия включает одни и те же операции: временное и фазовое согласование сабвуферов
с основной системой, частотную коррекцию, подготовку input list и сценического плана, сборку фонограмм и
программы воспроизведения, проверку каждого канала на саундчеке и контроль акустической обратной связи во время
выступления. Как правило, эти задачи решаются вручную, в нескольких разных программах и заново на каждой площадке.

**SSMT объединяет эти процессы в одном приложении и автоматизирует их там, где измерение и расчёт надёжнее
субъективной оценки. Программа измеряет, анализирует, предлагает и выполняет настройку, а творческие решения и
управление миксом остаются за звукорежиссёром.**

## ✨ Возможности

- 📐 **Настройка звукоусилительной системы** — пошаговая процедура на основе двухканального FFT-анализа:
  определение задержки и полярности, согласование сабвуферов с основной системой, расчёт параметрической
  коррекции на стандартных частотах процессора, контрольное измерение и отчёт в PDF. Поддерживаются
  калибровочные файлы измерительных микрофонов и типовые профили.
- 📋 **Input list и сценический план** — список каналов на основе шаблонов, мониторные миксы, сводная
  спецификация оборудования (микрофоны, DI, стойки, фантомное питание), сценический план. Экспорт в PDF, PNG
  и CSV для технического райдера.
- ▶️ **Qtrl — Show Control Center** — воспроизведение шоу по кью: запуск с точностью до сэмпла, фейды, группы,
  паузы, OSC-управление световыми, видео- и звуковыми системами (Resolume, ETC Eos, grandMA3, MagicQ, X32/M32,
  QLab), панель one-shot, таймлайн, двухступенчатая остановка и защита от повторного запуска.
- 🤖 **FOH Assist** *(beta)* — ассистент звукорежиссёра для микшерных пультов X32 / M32 и X Air с подключением
  по сети, по тому же принципу, что и Mixing Station:
  - 🎛️ **автоматический саундчек** — установка входного усиления, фильтра высоких частот, эквализации и
    компрессии для каждого канала; групповая настройка оркестра и хора по названиям каналов; баланс группы и
    поэтапное повышение уровня с контролем обратной связи; профили Мюзикл · Рок · Классика · Речь;
  - 🔄 **проверка полярности** — автоматическое сравнение пар микрофонов одного источника (kick in/out,
    snare top/bottom и др.) и установка корректной полярности;
  - 🛡️ **сопровождение шоу** — микс ведёт звукорежиссёр; ассистент подавляет обратную связь в зале,
    временно снижает уровень мониторной линии при возникновении самовозбуждения и восстанавливает его,
    сохраняет разборчивость солиста в массовых сценах. Фейдеры каналов ассистент не изменяет;
  - 🧪 **тест пульта и симуляция шоу** — проверка всего цикла работы с пультом на тестовом сценарии
    с последующим восстановлением исходных настроек.

<details>
<summary>📸 Скриншоты</summary>

| Настройка системы | Input list и сцена |
|---|---|
| ![](App/Tests/Snapshots/References/step7-eq.png) | ![](App/Tests/Snapshots/References/input-list.png) |
| **Qtrl** | **Отчёт** |
| ![](App/Tests/Snapshots/References/show-expert-show.png) | ![](App/Tests/Snapshots/References/report.png) |

</details>

## 💡 Преимущества

| | |
|---|---|
| ⏱️ **Экономия времени** | Настройка системы и саундчек выполняются по схеме «измерение → проверка → результат» вместо многочасовой ручной работы. |
| 🔁 **Воспроизводимость** | Решения основаны на измерениях, а не на субъективной оценке в шумном зале: результат документируется в отчёте и воспроизводится на следующей площадке. |
| 🛟 **Безопасность** | Автоматические коррекции ограничены несколькими децибелами, любое изменение отменяется одним действием, ручное управление звукорежиссёра всегда имеет приоритет. |
| 🧰 **Единая среда** | Измерения, документация, воспроизведение и управление пультом — в одном приложении. |
| 🎓 **Работа без оборудования** | Встроенные модели помещения и микшерного пульта позволяют освоить программу и проверить сценарий заранее. |

## 🚀 Начало работы

1. Загрузите `SSMT-<версия>.pkg` со страницы [Releases](../../releases/latest) и запустите установщик.
2. Приложение распространяется без подписи Apple Developer ID, поэтому macOS запросит подтверждение:
   **Системные настройки → Конфиденциальность и безопасность → «Всё равно открыть»**.
3. При первом запуске предоставьте доступ к микрофону.
4. Выберите раздел в боковой панели: **Настройка системы**, **Input list**, **Qtrl** или **FOH Assist**.

> [!TIP]
> Все функции доступны без оборудования: в разделе настройки системы выберите **«Симуляция (виртуальный зал)»**,
> в FOH Assist — **«Симулятор (без пульта)»**.

> [!IMPORTANT]
> Перед запуском «Теста пульта» или «Симуляции шоу» на реальном пульте сохраните текущую сцену и убедитесь, что
> на сцене нет исполнителей. Тест изменяет названия и параметры выбранных каналов (по завершении они
> восстанавливаются); на время теста главный выход отключается.

## 📚 Документация

- [Руководство пользователя (RU)](docs/USER_GUIDE.ru.md) · [User guide (EN)](docs/USER_GUIDE.en.md)
- [Установка](docs/INSTALL.md) · [Что нового](docs/RELEASE_NOTES.md) · [История версий](docs/CHANGELOG.md)
- [Статус функций](docs/STATUS.md) · [Принятые решения и допущения](docs/ASSUMPTIONS.md)

---

<details>
<summary>🇬🇧 English</summary>

**SSMT is a professional macOS tool for live sound engineers and system technicians: sound reinforcement
system alignment, event documentation, show playback and a mixing assistant in a single application.**

- 📐 **System setup** — guided sub ↔ mains alignment from dual-channel FFT measurements, delay and polarity,
  EQ suggestions on standard processor frequencies, verification and a PDF report; measurement-mic calibration.
- 📋 **Input list & stage plan** — channels from templates, monitor mixes, a pull list, a stage plot; PDF / PNG / CSV.
- ▶️ **Qtrl — Show Control Center** — cue-based playback with sample-accurate starts, fades, groups, OSC to
  lighting, video and consoles, one-shot pads, a timeline, two-stage Stop all.
- 🤖 **FOH Assist** *(beta)* — connects to Behringer X32 / Midas M32 and X Air over Wi-Fi like Mixing Station;
  tunes channels by itself, one-button orchestra and choir, automatic polarity check, a show guard that backs up
  the engineer without moving channel faders, plus a console test and a show simulation.

SSMT replaces hours of repetitive manual work with measured, repeatable and reversible procedures, while creative
decisions and control of the mix remain with the engineer. Requires macOS 13+ (Apple Silicon or Intel). [Download](../../releases/latest) ·
[User guide](docs/USER_GUIDE.en.md) · [Install](docs/INSTALL.md)

</details>

<details>
<summary>🛠️ Для разработчиков</summary>

| Path | What |
|---|---|
| `Packages/SSMTCore` | DSP, measurement engine, FOH Assist logic, simulation (no UI, no Core Audio). Tested on macOS and Linux. |
| `Packages/SSMTCore/Sources/SSMTRealtime` | C11 lock-free ring buffer and atomics for the audio thread |
| `Packages/SSMTAudio` | Core Audio HAL (AUHAL) duplex backend, device catalog |
| `App/SSMT` | SwiftUI app |
| `project.yml` | XcodeGen project spec |

```sh
brew install xcodegen      # free, build-time only
xcodegen generate
open SSMT.xcodeproj         # or: xcodebuild -scheme SSMT -configuration Release build
```

- Core tests: `swift test -c release --package-path Packages/SSMTCore`
  (Linux without a toolchain: `scripts/linux-swift.sh swift test -c release --package-path Packages/SSMTCore`).
- Snapshot tests (macOS): `xcodebuild test -scheme SSMT -configuration Debug -destination 'platform=macOS'`;
  references in `App/Tests/Snapshots/References` (CI records missing ones).
- Release: push a tag `vX.Y.Z` or run the CI workflow with `release_tag` → CI builds, ad-hoc signs, packages
  `SSMT-X.Y.Z.pkg` and publishes a GitHub Release.
- UI strings: `scripts/strings.py` (en + ru). Plan: [docs/PLAN.md](docs/PLAN.md) · Acceptance: [docs/ACCEPTANCE.md](docs/ACCEPTANCE.md)

</details>
