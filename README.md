<div align="center">

<img src="docs/media/icon.png" width="128" alt="SSMT">

# SSMT — SoundSolution Multi Tool

**Меньше рутины. Больше внимания звуку.**<br>
Настройка системы, подготовка сцены и управление шоу — в одном приложении для macOS.

[![Release](https://img.shields.io/github/v/release/wavessevaw/SSMT-Soundsolution-Multitool-?label=release&color=2EE59D)](../../releases/latest)
[![CI](https://github.com/wavessevaw/SSMT-Soundsolution-Multitool-/actions/workflows/ci.yml/badge.svg)](../../actions/workflows/ci.yml)
![macOS](https://img.shields.io/badge/macOS-13%2B-black?logo=apple)
![Apple Silicon | Intel](https://img.shields.io/badge/Apple%20Silicon%20%7C%20Intel-universal-10A86E)
![RU | EN](https://img.shields.io/badge/язык-RU%20%7C%20EN-A7F3D0)

<img src="docs/media/hero.png" alt="SSMT" width="100%">

</div>

> [!NOTE]
> **FOH Assist — бета-версия.** Взаимодействие с Behringer X32 / Midas M32 и X Air / MR реализовано
> на основе открытого описания протокола. Работа с физическим оборудованием пока не проверена.
> Для первичной проверки предусмотрен режим «Тест пульта» с восстановлением исходных настроек после завершения.

## Скачать

| Что | Для кого | Где |
|---|---|---|
| **SSMT** (установщик `.pkg`) | macOS 13+, Apple Silicon и Intel | [**Последний релиз**](../../releases/latest) |
| Руководство | Как пользоваться всеми функциями | [Русский](docs/USER_GUIDE.ru.md) · [English](docs/USER_GUIDE.en.md) |
| Установка | Первый запуск без подписи Apple Developer ID | [docs/INSTALL.md](docs/INSTALL.md) |

## От первого измерения до последней команды GO

Новая площадка, ограниченное время на монтаж, десятки каналов и шоу, которое должно начаться вовремя.
Нужно настроить акустическую систему, подготовить коммутацию, проверить микрофоны и собрать фонограммы
в точную последовательность.

**SSMT помогает пройти этот путь в одном приложении.** Измеряйте и настраивайте систему, готовьте
технический райдер, запускайте фонограммы и подключайте ассистента к микшерному пульту.
Меньше переключений между инструментами — больше внимания исполнителям и звучанию.

Для звукорежиссёров и системных инженеров, работающих на концертах, спектаклях и выездных мероприятиях.

## Четыре инструмента для вашей работы

### Настройка системы — от измерения к решению

Получите данные для согласования сабвуферов с основными акустическими системами:
задержка, полярность и рекомендации по эквализации. Пошаговый мастер помогает провести измерение,
внести настройки и проверить результат. Сохраните отчёт в PDF, чтобы вернуться к нему на следующем выезде.

Двухканальный FFT-анализ, калибровочные файлы измерительных микрофонов и типовые профили —
в основе каждого этапа настройки.

### Input list и план сцены — площадка знает, что вам нужно

Соберите каналы из шаблонов, спланируйте мониторные миксы и размещение оборудования.
Получите перечень микрофонов, DI-боксов и стоек с указанием фантомного питания.
Экспортируйте материалы в PDF, PNG или CSV и передайте площадке готовую основу технического райдера.

### Qtrl — шоу начинается с GO

Подготовьте последовательность фонограмм и команд: точный запуск, плавные изменения уровня,
группы, паузы и кнопки однократного воспроизведения. Временная шкала помогает видеть ход шоу,
а общая остановка и защита от повторного GO дают контроль в ответственный момент.

Запуск с точностью до сэмпла и управление по OSC связывают звук, свет и видео:
Resolume, ETC Eos, grandMA3, MagicQ, X32/M32 и QLab.

### FOH Assist — дополнительное внимание за пультом

Ассистент для X32 / M32 и X Air помогает с настройкой каналов и контролем звука во время мероприятия.
Подключение по Wi-Fi, профили «Мюзикл», «Рок», «Классика» и «Речь», обработка каналов оркестра и хора
с распознаванием по названиям.

- **На саундчеке:** входное усиление, фильтрация низких частот, эквализация, компрессия
  и проверка полярности парных микрофонов.
- **Во время шоу:** подавление акустической обратной связи, контроль проблемных мониторных каналов
  и поддержание разборчивости солиста в массовых сценах.
- **Перед работой:** тест взаимодействия с пультом и симуляция мероприятия
  с восстановлением исходных настроек.

**Вы управляете миксом. Ассистент помогает следить за деталями, не изменяя положения фейдеров каналов.**

FOH Assist находится в бета-версии; работа с физическими пультами пока не проверена.

<details>
<summary>Скриншоты</summary>

| Настройка системы | Input list и сцена |
|---|---|
| ![](App/Tests/Snapshots/References/step7-eq.png) | ![](App/Tests/Snapshots/References/input-list.png) |
| **Qtrl** | **Отчёт** |
| ![](App/Tests/Snapshots/References/show-expert-show.png) | ![](App/Tests/Snapshots/References/report.png) |

</details>

## Почему SSMT

| Ваша задача | Что даёт SSMT |
|---|---|
| **Подготовиться к новой площадке** | Измерения, рекомендации и проверка результата в пошаговом мастере. |
| **Передать понятный райдер** | Input list, план сцены и перечень оборудования с экспортом в привычные форматы. |
| **Провести шоу по плану** | Фонограммы и OSC-команды в единой последовательности с точным запуском. |
| **Сохранить контроль** | Приоритет ручного управления, ограниченные автоматические корректировки и отмена изменений. |
| **Освоить инструменты заранее** | Виртуальный зал и симулятор пульта для знакомства с рабочим процессом без оборудования. |

**Начните с виртуального зала — затем переходите к своей площадке.**
[Скачать SSMT для macOS](../../releases/latest)

## Быстрый старт

1. Скачайте `SSMT-<версия>.pkg` со страницы [Releases](../../releases/latest) и откройте его.
2. macOS предупредит о неподтверждённом разработчике (бесплатная программа без подписи Apple Developer ID):
   **Системные настройки → Конфиденциальность и безопасность → «Всё равно открыть»**.
3. При первом запуске разрешите доступ к микрофону.
4. Выберите функцию в боковой панели: **Настройка системы**, **Input list**, **Qtrl** или **FOH Assist**.

> [!TIP]
> Для ознакомления без подключения оборудования в настройке системы выберите **«Симуляция (виртуальный зал)»**, а в FOH Assist —
> **«Симулятор (без пульта)»**: режимы позволяют изучить рабочий процесс без аудиоинтерфейса и микшерного пульта.

> [!IMPORTANT]
> Перед запуском «Теста пульта» и «Симуляции шоу» на физическом оборудовании сохраните сцену пульта
> и убедитесь, что на сцене нет исполнителей. Тест изменяет названия и параметры выбранных каналов
> с последующим восстановлением исходных настроек; основной выход на время проверки отключается.

## Документация

- [Руководство пользователя (RU)](docs/USER_GUIDE.ru.md) · [User guide (EN)](docs/USER_GUIDE.en.md)
- [Установка](docs/INSTALL.md) · [Что нового](docs/RELEASE_NOTES.md) · [История версий](docs/CHANGELOG.md)
- [Статус функций](docs/STATUS.md) · [Принятые решения и допущения](docs/ASSUMPTIONS.md)

---

<details>
<summary>English</summary>

**Less routine. More focus on sound.**

SSMT brings system setup, stage preparation and show control into one macOS application for live sound
engineers and system engineers. From your first measurement to the final GO, keep your tools together
and your attention on the performance.

- **System setup — turn measurements into decisions.** Align subwoofers with the main loudspeaker
  system using dual-channel FFT analysis, delay and polarity assessment, and EQ recommendations.
  Verify your adjustments and save a PDF report. Supports measurement microphone calibration files.
- **Input list and stage plan — give the venue a clear brief.** Build channel lists from templates,
  plan monitor mixes and equipment placement, and export your documentation as PDF, PNG or CSV.
- **Qtrl — put the show on GO.** Organize playback and OSC commands with sample-accurate starts,
  fades, groups, pauses, one-shot triggers and a timeline. Includes a two-stage stop-all function.
- **FOH Assist — extra attention at the console.** Connect to X32 / M32 or X Air over Wi-Fi for
  assisted channel setup, orchestra and choir processing, polarity checks and feedback control.
  The engineer keeps control of the mix; the assistant does not move channel faders.

FOH Assist is in beta, based on publicly available protocol documentation, and has not yet been verified
with physical consoles. Console testing and show simulation restore initial settings after completion.

Explore the workflow with a virtual venue and console simulator before connecting equipment.
Requires macOS 13+ (Apple Silicon or Intel).
[Download](../../releases/latest) · [User guide](docs/USER_GUIDE.en.md) · [Install](docs/INSTALL.md)

</details>

<details>
<summary>Для разработчиков</summary>

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

