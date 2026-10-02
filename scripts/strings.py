#!/usr/bin/env python3
"""Source of truth for UI strings (en, ru). Generates App/SSMT/Resources/Localizable.xcstrings
and verifies that every key used in Swift sources exists.

Usage: scripts/strings.py generate | check
"""
import json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "App/SSMT/Resources/Localizable.xcstrings")

STRINGS = {
    "app.title": ("SSMT · SYSTEM SETUP", "SSMT · НАСТРОЙКА СИСТЕМЫ"),
    "app.subtitle": ("SoundSolution Multi Tool", "SoundSolution Multi Tool"),
    "action.stop": ("STOP", "STOP"),
    "action.stop.help": ("Mute the test signal immediately (Esc)", "Мгновенно заглушить тестовый сигнал (Esc)"),
    "noise.start": ("Start noise", "Включить шум"),
    "noise.on": ("Noise on", "Шум включён"),
    "noise.toggle": ("Noise on/off", "Шум вкл/выкл"),
    "noise.pink": ("Pink noise (random)", "Розовый шум (случайный)"),
    "noise.white": ("White noise", "Белый шум"),
    "noise.periodic": ("Periodic pink (fast)", "Периодический розовый (быстрый)"),
    "noise.periodic.hint": ("Fast mode: coherence is not meaningful with periodic noise.",
                            "Быстрый режим: с периодическим шумом когерентность не имеет смысла."),
    "engine.running": ("Running", "Работает"),
    "engine.stopped": ("Stopped", "Остановлено"),
    "engine.dropouts": ("Dropouts", "Пропуски"),
    "engine.start": ("Start audio", "Запустить аудио"),
    "engine.stop": ("Stop audio", "Остановить аудио"),
    "delay.find": ("Find delay", "Найти задержку"),
    "delay.searching": ("Searching…", "Поиск…"),
    "delay.locked": ("DELAY LOCKED", "ЗАДЕРЖКА ЗАФИКСИРОВАНА"),
    "delay.unreliable": ("Delay not found reliably. Raise the level or check the microphone.",
                         "Задержка найдена ненадёжно. Поднимите уровень или проверьте микрофон."),
    "setup.source": ("Source", "Источник"),
    "setup.interface": ("Interface", "Интерфейс"),
    "setup.simulation": ("Simulation (virtual room)", "Симуляция (виртуальный зал)"),
    "setup.mic.channel": ("Microphone input", "Вход микрофона"),
    "setup.output.channel": ("Signal output", "Выход сигнала"),
    "setup.ref.channel": ("Reference input", "Вход референса"),
    "setup.no48k": ("Device does not support 48 kHz", "Устройство не поддерживает 48 кГц"),
    "setup.reference": ("Reference", "Референс"),
    "setup.temperature": ("Air temperature", "Температура воздуха"),
    "setup.refresh": ("Refresh device list", "Обновить список устройств"),
    "setup.generator": ("Generator", "Генератор"),
    "setup.noise": ("Signal", "Сигнал"),
    "setup.level": ("Level", "Уровень"),
    "setup.max.level": ("Maximum level", "Максимальный уровень"),
    "setup.output.level": ("Output now", "Выход сейчас"),
    "ref.internal": ("Internal (no cable)", "Внутренний (без кабеля)"),
    "ref.loopback": ("Loopback cable", "Кабель loopback"),
    "ref.internal.hint": ("The generated signal is the reference. Only the microphone and one output are needed.",
                          "Референс — сам генерируемый сигнал. Нужны только микрофон и один выход."),
    "ref.loopback.hint": ("Connect a cable from the signal output to the reference input.",
                          "Соедините кабелем выход сигнала со входом референса."),
    "safety.hf.warning": ("High noise levels can damage HF drivers. Raise the level gradually.",
                          "Высокий уровень шума может повредить ВЧ-драйверы. Поднимайте уровень постепенно."),
    "permission.denied": ("Microphone access denied. Allow SSMT in System Settings → Privacy & Security → Microphone.",
                          "Нет доступа к микрофону. Разрешите SSMT в Системных настройках → Конфиденциальность и безопасность → Микрофон."),
    "sim.title": ("Virtual system", "Виртуальная система"),
    "sim.hint": ("Simulates muting groups on the processor.", "Имитирует мьют групп на процессоре."),
    "sim.sub": ("Subwoofers on", "Сабвуферы включены"),
    "sim.main": ("Mains (satellites) on", "Сателлиты включены"),
    "display.title": ("Display", "Отображение"),
    "display.smoothing": ("Smoothing", "Сглаживание"),
    "display.smoothing.none": ("None", "Нет"),
    "display.coherence.threshold": ("Coherence threshold", "Порог когерентности"),
    "display.reset.avg": ("Reset averages", "Сбросить усреднение"),
    "display.reset.clip": ("Reset clip", "Сбросить клиппинг"),
    "settings.language": ("Language", "Язык"),
    "language.system": ("System", "Системный"),
    "meters.title": ("Inputs", "Входы"),
    "meters.mic": ("Microphone", "Микрофон"),
    "meters.ref": ("Reference", "Референс"),
    "meters.clip": ("CLIP", "КЛИП"),
    "meters.coherence": ("Coherence", "Когерентность"),
    "meters.averages": ("Averages", "Усреднений"),
    "meters.delay": ("Delay", "Задержка"),
    "quality.good": ("Good", "Хорошо"),
    "quality.weak": ("Weak", "Слабо"),
    "quality.repeat": ("Repeat", "Повторить"),
    "quality.none": ("No data", "Нет данных"),
    "graphs.title": ("Transfer function", "Передаточная функция"),
    "graphs.empty": ("Start the audio and the noise to see the measurement.",
                     "Запустите аудио и шум, чтобы увидеть измерение."),
    "graph.magnitude": ("Magnitude", "АЧХ"),
    "graph.phase": ("Phase", "Фаза"),
    "graph.coherence": ("Coherence", "Когерентность"),
    "action.cancel": ("Cancel", "Отмена"),
    "setup.split": ("Separate input and output devices", "Разные устройства для входа и выхода"),
    "setup.split.hint": ("SSMT creates a private aggregate device with drift correction so both run on one clock.",
                         "SSMT создаст частное агрегатное устройство с коррекцией дрейфа, чтобы вход и выход работали от одних часов."),
    "setup.input.device": ("Microphone device", "Устройство микрофона"),
    "setup.output.device": ("Output device", "Устройство выхода"),
    "autolevel.run": ("Auto level", "Автоуровень"),
    "autolevel.help": ("Measures room noise, then raises the level until SNR ≥ 20 dB or the maximum level.",
                       "Замеряет шум помещения, затем поднимает уровень до SNR ≥ 20 dB или до максимального уровня."),
    "autolevel.noise": ("Measuring room noise — keep quiet…", "Замер шума помещения — тишина…"),
    "autolevel.raising": ("Raising level…", "Поднимаю уровень…"),
    "autolevel.ok": ("Level %.0f dBFS · SNR %.0f dB", "Уровень %.0f dBFS · SNR %.0f dB"),
    "autolevel.max": ("Maximum reached · SNR only %.0f dB", "Достигнут максимум · SNR только %.0f dB"),
    "autolevel.clipped": ("Clipping — level reduced", "Клиппинг — уровень снижен"),
    "cal.title": ("Calibration", "Калибровка"),
    "cal.mic": ("Microphone", "Микрофон"),
    "cal.mic.none": ("None", "Нет"),
    "cal.mic.uncalibrated": ("Microphone not calibrated", "Микрофон не откалиброван"),
    "cal.points": ("%ld points", "%ld точек"),
    "cal.remove": ("Remove from library", "Удалить из библиотеки"),
    "cal.import": ("Import calibration file…", "Импорт файла калибровки…"),
    "cal.spl": ("SPL calibration", "Калибровка SPL"),
    "cal.spl.none": ("SPL not calibrated", "SPL не откалиброван"),
    "cal.apply": ("Apply", "Применить"),
    "cal.calibrator": ("Read calibrator", "Считать калибратор"),
    "cal.calibrator.help": ("Put the calibrator on the microphone; the test signal is switched off.",
                            "Наденьте калибратор на микрофон; тестовый сигнал будет выключен."),
    "spl.reset": ("Reset SPL", "Сбросить SPL"),
}

DYNAMIC_PREFIXES = {"graph.": ["graph.magnitude", "graph.phase", "graph.coherence"]}


def generate():
    catalog = {"sourceLanguage": "en", "version": "1.0", "strings": {}}
    for key in sorted(STRINGS):
        en, ru = STRINGS[key]
        catalog["strings"][key] = {
            "extractionState": "manual",
            "localizations": {
                "en": {"stringUnit": {"state": "translated", "value": en}},
                "ru": {"stringUnit": {"state": "translated", "value": ru}},
            },
        }
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(catalog, f, ensure_ascii=False, indent=2)
        f.write("\n")


def check():
    used = set()
    for dirpath, _, files in os.walk(os.path.join(ROOT, "App")):
        for name in files:
            if name.endswith(".swift"):
                text = open(os.path.join(dirpath, name), encoding="utf-8").read()
                used |= set(re.findall(r'\.t\("([a-z0-9.]+)"', text))
                used |= set(re.findall(r'"((?:noise|ref|graph)\.[a-z.]+)"', text))
    missing = sorted(k for k in used if k not in STRINGS and not k.endswith("."))
    for keys in DYNAMIC_PREFIXES.values():
        missing += [k for k in keys if k not in STRINGS]
    generated = json.load(open(OUT, encoding="utf-8"))
    stale = sorted(set(STRINGS) ^ set(generated["strings"]))
    if missing or stale:
        print("Missing keys:", missing)
        print("Catalog out of date:", stale)
        sys.exit(1)
    print(f"OK: {len(used)} keys used, {len(STRINGS)} defined")


if __name__ == "__main__":
    {"generate": generate, "check": check}[sys.argv[1] if len(sys.argv) > 1 else "check"]()
