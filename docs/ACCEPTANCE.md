# Критерии приёмки функции №1 — сверка

| # | Критерий (ТЗ, раздел 10) | Как подтверждено | Статус |
|---|---|---|---|
| 1 | Пользователь без знаний о фазе проходит мастер до отчёта, видя только понятные карточки | Мастер 0–8 + итог: карточки действий, приборы-тюнеры, «качество сигнала» вместо когерентности; фазы/когерентности нет вне «Эксперта». Снапшоты `App/Tests/Snapshots/References/*`. Тест `WizardTests` проходит мастер целиком на симуляции | ✅ в симуляции · ☐ ручная проверка на реальной системе (STATUS п. 12–16) |
| 2 | В симуляции после рекомендаций провал на кроссовере < 3 dB, СКО от цели падает ≥ 2× или до порога | `AlignmentTests.testRecommendationRemovesCrossoverDipInRealisticRoom`, `WizardTests.testFullWizardInSimulation` (провал < 3 dB, «Отлично»); `EQTests.testEQImprovesSimulatedRoom` (СКО ≥ 2× / ≤ 1.5 dB), `WizardTests.testEQStepsInSimulation`; golden `GoldenTests` | ✅ автотесты |
| 3 | Мини-окно живёт при свёрнутом главном окне и обновляется в реальном времени | NSPanel вне окна, авто-показ при сворачивании; движок независим от окон (`MeasurementEngine` в модели, тест `EngineTests.testRealtimeSimulationThreadProducesSnapshots`); снапшот `mini-window` | ✅ архитектура и тесты · ☐ ручная проверка (STATUS п. 18) |
| 4 | STOP глушит выход мгновенно из любого состояния | Атомарный флаг, тишина со следующего аудиобуфера: `EngineTests.testEmergencyStopSilencesNextBuffer`, `SignalTests.testHardMuteSilencesImmediately`; Esc — локальный монитор клавиш + меню; STOP в окне, «Сцене» и мини-окне | ✅ автотесты · ☐ ручная проверка с картой |
| 4а | Холодный старт: экран с логотипом → плавный переход, логотип остаётся в углу | `LaunchState`/`RootView` (matchedGeometry, Reduce Motion, только холодный старт); снапшот `splash` | ✅ · ☐ ручная проверка (STATUS п. 17); логотип SoundSolutions встроен (растр, вектор — по готовности) |
| 5 | Все допущения зафиксированы в `docs/ASSUMPTIONS.md` | A1–A72 | ✅ |
| 6 | Работа на старых Mac (Intel, встроенная графика) без «лагов» | Живые данные отдельно от модели, расчёты тюнера вне главного потока, «Облегчённая графика»; анализатор ≈ 17 мс на 1 с звука, показание тюнера ≈ 4 мс — сторожевые тесты `PerformanceTests` | ✅ автотесты · ☐ ручная проверка на MacBook Pro 2017 |
| 7 | Пропажа звуковой карты не «вешает» программу | Сторож «звук не поступает > 1.5 с» останавливает замер и движок с понятным сообщением; отключение/смена частоты/перегрузка устройства сбрасывают зафиксированную задержку | ✅ · ☐ ручная проверка (выдернуть USB во время замера) |

## Требования к тестам (раздел 10)

| Требование | Тесты |
|---|---|
| Известная задержка ±1 отсчёт, полярность в обеих ориентациях | `AlignmentTests.testFindsKnownDelayWithinOneSampleBothSigns`, `testDetectsInvertedSubPolarity` |
| Известный фильтр: PEQ уменьшает ошибку, не поднимает провалы, соблюдает лимиты | `EQTests.testFitsKnownPeaks`, `testNoBoostIntoNarrowDip`, `testBoostAndCutLimits` |
| Гребёнка/узкие провалы не «лечатся» | `EQTests.testCombFilteringIsNotTreated`, `testNoBoostIntoNarrowDip` |
| Точность H при заданном SNR, когерентность падает где должна | `AnalyzerTests.testTransferFunctionAccuracyAtModerateSNR`, `testCoherenceFollowsSignalToNoiseRatio` |
| Delay finder до 500 мс с шумом и без | `DelayFinderTests` |
| Мульти-окно без разрывов | `AnalyzerTests.testMultiWindowStitchingIsContinuous` |
| Производительность (сторож) | `PerformanceTests` |
| Регрессия: golden-файлы | `GoldenTests` (`Tests/SSMTCoreTests/Golden/demo-session.json`) |
| UI: скриншот-тесты экранов и мини-окна | `App/Tests/Snapshots/SnapshotTests.swift` (13 снимков, сравнение с эталонами в CI) |
| Ручной чек-лист «сворачивание не прерывает измерение» | `docs/STATUS.md`, п. 7 и 18 |

Итого автотестов: ядро — 84 (Linux + macOS), снапшоты — 13 (macOS).
