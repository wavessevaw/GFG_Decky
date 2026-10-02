# SSMT 0.9.0 — первая публичная версия · first public version

## Русский

**Автоматическая настройка звуковой системы** — функция №1 SoundSolution Multi Tool.

- Мастер из 5 этапов: подготовка (чек-лист, автоуровень, задержка) → замеры (система, сабы, топы) →
  выравнивание саб ↔ топы (задержка, полярность, уровень) по стрелочным приборам → EQ по зоне
  прослушивания с подстройкой по полосам → итог, отчёт PDF/PNG, экспорт фильтров, сессия.
- Двухканальный анализ (опорный сигнал — генерируемый шум), когерентность, SPL с калибровкой.
- Коррекция микрофона: ваши файлы калибровки и 22 встроенных типовых профиля (Shure SM81,
  Soyuz 011/013 FET, Soyuz 022 Bomblet, AKG C414 XLII и др., точность ±2–3 дБ).
- Режимы «Мастер» / «Эксперт», «Сцена» (крупные цифры), мини-окно, STOP / Esc, русский и английский.
- Симуляция: весь мастер можно пройти без оборудования.

**Ограничения версии 0.9:** проверена в симуляции и автотестах; проверка на реальных системах идёт.
Приложение не подписано Apple Developer ID — см. установку ниже.

## English

**Automatic sound system setup** — function #1 of SoundSolution Multi Tool: a 5-stage wizard
(prepare → measure → sub/mains alignment by needle gauges → zone-averaged EQ entered band by band →
report, filter export, session), dual-channel analysis, SPL, microphone correction (your files plus
22 typical built-in profiles, ±2–3 dB), Wizard/Expert/Stage modes, mini window, Russian and English,
and a full simulation. Version 0.9 is verified in simulation and automated tests; field testing is
ongoing. Not signed with an Apple Developer ID — see installation below.

---

# Установка SSMT · Installing SSMT

## Русский

1. Скачайте `SSMT-<версия>.pkg` со страницы **Releases** репозитория.
2. Откройте файл. macOS предупредит, что разработчик не подтверждён: приложение распространяется
   бесплатно, без платной подписи Apple Developer ID.
   - **macOS 15 и новее:** нажмите «Готово», затем **Системные настройки → Конфиденциальность и безопасность**
     → внизу «SSMT-….pkg заблокирован» → **«Всё равно открыть»** → подтвердите паролем.
   - **macOS 13–14:** правый клик по файлу → **«Открыть»** → «Открыть».
3. Пройдите установщик — SSMT появится в «Программах».
4. При первом запуске SSMT может снова спросить подтверждение (как в п. 2) — это нормально.
5. При первом запуске измерения разрешите **доступ к микрофону**. Если отказали: Системные настройки →
   Конфиденциальность и безопасность → Микрофон → включите SSMT.

Требования: macOS 13 Ventura или новее, Mac на Apple Silicon или Intel, звуковая карта с входом для
измерительного микрофона (фантомное питание) и выходом в тракт системы.

После обновления версии macOS может заново спросить разрешение на микрофон — это следствие подписи без
Developer ID.

## English

1. Download `SSMT-<version>.pkg` from the repository **Releases** page.
2. Open it. macOS warns that the developer cannot be verified: SSMT is distributed for free, without a paid
   Apple Developer ID signature.
   - **macOS 15+:** click Done, then **System Settings → Privacy & Security** → "SSMT-….pkg was blocked"
     → **Open Anyway** → confirm.
   - **macOS 13–14:** right-click the file → **Open** → Open.
3. Complete the installer; SSMT is placed in Applications.
4. The first launch of SSMT may ask for the same confirmation.
5. Allow **microphone access** when asked (System Settings → Privacy & Security → Microphone).

Requirements: macOS 13 Ventura or later, Apple Silicon or Intel Mac, an audio interface with a measurement
microphone input (phantom power) and an output into the sound system.
