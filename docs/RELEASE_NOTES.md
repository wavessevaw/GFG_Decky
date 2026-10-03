# SSMT 1.2.0 — Qtrl, Show Control Center

## Русский

**Новое: функция №3 — Qtrl, Show Control Center.** Третий раздел в боковой панели.

- **Шоу из кью:** аудио, фейд, группа (все вместе, по очереди, плейлист, случайная), пауза, заметка, OSC и
  управляющие кью (старт, стоп, пауза, загрузка, сброс, перейти, сменить цель, включить/выключить, выход
  из петли). Пауза до и после, «затем»: ждать GO / следующая после паузы / следующая по окончании.
- **Два вида:** «Простой» (список и одна панель сбоку) и «Эксперт» (библиотека, кнопки one-shot на F1–F12,
  широкий мультитрековый таймлайн). Режимы «Правка» и «Шоу» (правка заблокирована).
- **Звук:** старты точны до сэмпла; любые форматы, которые читает macOS, включая звук из видеофайлов;
  файлы раскладываются в кэш на диске и читаются заранее — память не забивается, GO не ждёт диск.
  Редактор волны: начало, конец, нарастание, затухание, петля внутри трека, прослушивание с любого места.
  До 64 выходов с матрицей «канал файла → выход».
- **OSC:** мастер подключения Resolume, ETC Eos, grandMA3, ChamSys MagicQ, Behringer X32 / Midas M32 и QLab
  с подсказками, проверкой связи и предупреждением о другой сети; готовые команды и OSC-монитор.
- **Надёжность:** «Стоп всё» (Esc) — плавно, повторно — мгновенно; защита от двойного GO; проверка шоу
  (пропавшие и неготовые файлы, цели, номера, клавиши); поиск пропавших файлов; выход сам восстанавливается
  после сбоя карты; Mac не засыпает, пока открыт Qtrl; выбор аудиобуфера.

Функции №1 и №2 — без изменений.

## English

**New: function #3 — Qtrl, Show Control Center.** Cue-based show playback: audio, fade, group, wait,
memo, OSC and control cues; pre/post-wait and continue modes; Simple and Expert views (one-shot pads
on F1–F12, wide multitrack timeline); sample-accurate starts; any format macOS reads, including the
sound of video files, cached on disk and read ahead; waveform editor with an inner loop; up to 64
outputs; OSC with guided setup for Resolume, ETC Eos, grandMA3, MagicQ, X32/M32 and QLab; two-stage
Stop all, double-GO guard, pre-show check, automatic output recovery, no sleep while Qtrl is open.

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
