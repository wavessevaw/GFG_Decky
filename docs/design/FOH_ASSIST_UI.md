# FOH Assist — interface redesign proposal (for review)

Status: **proposal, not implemented.** Mockups: [`foh-assist-soundcheck.png`](foh-assist-soundcheck.png) ·
[`foh-assist-show.png`](foh-assist-show.png) (HTML sources next to them). Current screens for comparison:
`App/Tests/Snapshots/References/assist.png`, `assist-show.png` (on `main`).

## Problems in the current interface (1.2.0)

| # | Where | Problem |
|---|---|---|
| 1 | Soundcheck, channel table | Fixed column widths: «Настраиваю» / «Настроить» break mid-word; the EQ list runs into the compressor column; nine columns compete for one row. |
| 2 | Soundcheck | The state of a channel being tuned is only a badge; what the assistant changes is in a separate log far below. No view of the EQ curve. |
| 3 | Soundcheck | Long scrolling page: console settings, one-button actions, table, log stacked vertically; the table does not fit on screen. |
| 4 | Show | Large empty area under the console panel; the guard's state is a small badge; active corrections are not visible as a list. |
| 5 | Show | Monitor buses are toggle chips without levels — the engineer cannot see which line is ringing. |
| 6 | Both | Connection / microphone / profile settings take a full panel although they change rarely. |
| 7 | Both | Old wording ("фидбэк", "зазвеневший монитор") — already fixed in strings on the claude branch. |

## Proposal

**Common header (both modes):** title, mode switch (Саундчек · Шоу · Тест пульта) and compact status chips on the
right — console (address, channels, connection dot), measurement mic and SPL, profile. A gear opens the full settings
(console, audio interface, inputs, tap point) as a sheet: rarely changed, not on the main screen.

**Soundcheck — master/detail:**
- Action bar: Оркестр, Хор, channel range, «Проверить полярность»; on the right the running job with a progress bar,
  «Откатить», «Стоп».
- Left: channel list grouped by family (ударные, хор, вокал…), each row = number, name, recognised source and a
  one-line summary, a live level meter, a status badge (не настроен · ждёт сигнал · настраиваю · готово · полярность).
  No fixed-width numeric columns → nothing wraps.
- Right: the selected channel in detail — gain, HPF, compressor, remaining tonal deviation as tiles; the **EQ curve**
  (current on the console vs. where the assistant is heading); the four bands; this channel's log; «Настроить»,
  «Откатить канал».

**Show — state first:**
- A status banner: guard on/off, active corrections, total for the show, show time; «Симуляция шоу», «Снять страховку».
- A strip of monitor buses with **live level bars**; a ringing line is highlighted with what was done and the
  countdown to restore.
- «Активные коррекции» as a list: what, where, how much, when it is released, and a per-item «Отменить».
- Leads to keep intelligible as chips with «+ добавить».
- Log on the right, the engineer's own actions in a different colour.

**Console test:** the same header; the report as a vertical stepper (step → status → detail) instead of a table.

## Questions for the reviewer (Codex)

1. Layout: master/detail for soundcheck vs. a wider table with an expandable row — which is clearer at 1100–1500 px?
2. SwiftUI implementation: `Table` (macOS 13) vs. `List` with custom rows for the channel list (sorting, selection,
   performance with 32–64 channels updating every 2 s)?
3. Level meters: drive them from the console meter stream at ~10 Hz without redrawing the whole view — suggested
   approach (separate `ObservableObject` for meters, `Canvas`, `TimelineView`)?
4. EQ curve: reuse `Graphs/TransferPlotView` / `FrequencyAxis` or a lighter dedicated view?
5. Accessibility / small screens (1100 × 720 minimum window): what collapses first?
6. Anything missing for a live show (e.g. a «freeze» switch, per-channel guard opt-out, undo history)?

## Constraints

- No changes to SSMTCore behaviour; the interface only presents what `AssistStore` already exposes (plus meters).
- RU/EN strings through `scripts/strings.py`; snapshot tests for every mode; minimum window 1100 × 720.
- Implementation by Claude on the claude branch after the review; Codex's PR #2 does not touch `App/`.
