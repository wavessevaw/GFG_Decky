# SSMT 1.0.0 — SoundSolution Multi Tool

## Русский

**Автоматическая настройка звуковой системы** — функция №1 SoundSolution Multi Tool.

- **Мастер из 5 этапов:** подготовка (чек-лист: звуковая карта, микрофон, автоуровень, задержка тракта) →
  замеры (вся система, только сабы, только сателлиты) → склейка сабов и сателлитов по фазе (задержка,
  полярность, уровень) с живыми стрелками-тюнерами → EQ по зоне прослушивания с вводом полос по стрелке →
  итог, отчёт PDF/PNG, экспорт фильтров TXT/CSV, сессия.
- **Надёжная склейка:** совпадение фаз по всей полосе перекрытия, защита от «проскока» на период по времени
  прихода звука, предупреждение о неоднозначных решениях, проверочный замер «прогноз ↔ факт».
- **EQ:** полосы на стандартных частотах ISO 1/3 октавы (или 1/6, или любые), по возрастанию; только мягкие
  подъёмы, провалы и интерференция не «лечатся».
- **Микрофоны:** ваши файлы калибровки и 22 встроенных типовых профиля (Shure SM81, Soyuz 011/013 FET,
  Soyuz 022 Bomblet, AKG C414 XLII и др., точность ±2–3 дБ).
- **Звуковые карты:** любые через Core Audio (USB, Thunderbolt, Dante/AVB), вход и выход на разных устройствах.
- **Интерфейс:** «Мастер» / «Эксперт», «Сцена» (крупные цифры), мини-окно, STOP / Esc, русский и английский;
  «Облегчённая графика» для старых Mac (включается автоматически на Intel).
- **Симуляция:** весь мастер можно пройти без оборудования.

**Что нового по сравнению с 0.9.x:** анализ звука вдвое быстрее; показания тюнеров не нагружают интерфейс;
программа корректно останавливается, если звуковая карта пропала (раньше замер мог «зависнуть»);
сообщения об ошибках видны на любом экране; уборка неиспользуемого кода.

Приложение не подписано Apple Developer ID — см. установку ниже.

## English

**Automatic sound system setup** — function #1 of SoundSolution Multi Tool: a 5-stage wizard (prepare →
captures → sub/satellite phase alignment with live needle tuners → zone-averaged EQ entered band by band →
report, filter export, session); robust alignment (phase match over the overlap band, cycle-slip
rejection by arrival time, ambiguity warning, verification capture); EQ bands on ISO 1/3-octave
frequencies in ascending order; microphone correction (your files + 22 typical profiles, ±2–3 dB); any
Core Audio interface; Wizard/Expert/Stage modes, mini window, Russian and English, reduced graphics for
older Macs; full simulation.

New since 0.9.x: twice-as-fast analysis, tuner readings off the main thread, a clean stop when the audio
interface disappears, error messages visible on every screen, dead-code cleanup.

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
