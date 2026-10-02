# SSMT 1.1.0 — Input list и стейдж-план · Input list and stage plan

## Русский

**Новое: функция №2 — конструктор input list и стейдж-плана.** В боковой панели переключатель
«Настройка системы / Input list и сцена».

- **Шоу:** артист, мероприятие, площадка, дата, инженер, контакт, заметки — в шапке каждого листа.
- **Каналы:** добавить, дублировать, переместить (кнопками или перетаскиванием), удалить, перенумеровать
  (ручные пропуски сохраняются); шаблоны групп (ударные 10/4, бас, гитары, клавиши, вокал, бэки,
  фонограмма, перкуссия, зальные, толкбэк); стереопара L/R; автозаполнение входов стейджбокса;
  подсказки моделей микрофонов и автоматическое +48 V для конденсаторов и активных DI; цвет группы;
  проверки (повтор номера или входа, пустой источник).
- **Мониторные миксы** (монитор, ушной, сайдфилл, драм-филл, стерео) и сводка **«Что выдать на сцену»**
  (микрофоны, DI, стойки, +48 V).
- **Стейдж-план:** 18 простых векторных символов оборудования и текст; перетаскивание с привязкой 25 см,
  поворот, размер, подписи и «каналы/микс», слои, сдвиг стрелками; размер сцены в метрах.
- **Экспорт:** PDF (A4 альбом, чёрным по белому: каналы, миксы и сводка, сцена), PNG (input list, сцена),
  CSV (каналы, миксы). Файлы `.ssmtinput`, автосохранение, отмена ⌘Z.

Функция №1 (автоматическая настройка системы) — без изменений по сравнению с 1.0.0.

## English

**New: function #2 — input list and stage plan builder** (sidebar switch "System setup / Input list &
stage plan"): show header; channel tools (add, duplicate, move, delete, renumber, group templates,
stereo pairs, stage box numbering, mic suggestions with automatic +48 V, group colours, checks);
monitor mixes and a pull list; a quick stage plan with 18 vector equipment symbols and text (drag with
25 cm snap, rotate, resize, captions, layers); export to PDF, PNG and CSV; `.ssmtinput` files, autosave
and undo. Function #1 is unchanged since 1.0.0.

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
