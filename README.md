# SwitcherLM

macOS menu-bar app that automatically detects and fixes keyboard layout mistakes as you type — and learns your typing habits over time using on-device ML.

**Example:** You start typing Russian but the keyboard is in English mode. You type `ghbdtn` and press Space. SwitcherLM instantly replaces it with `привет` and switches the layout.

---

## Recent updates (v1.0.4)

- **Screen flash** — brief translucent pulse on every auto-conversion (red = switched to EN, blue = RU). Configurable in Settings.
- **Conversion toast** — the toast now shows the word pair (`EN  ghbdtn → привет`) instead of just the language badge. Configurable in Settings.
- **App Filters** — blacklist apps where SwitcherLM should stay silent (e.g. Terminal, IDE). Menu-bar → App Filters…
- **Exceptions export / import** — back up or share your exceptions list as plain text. Exceptions → Export… / Import…
- **Password field detection** — auto-conversion is automatically skipped in secure text fields (password inputs) via the Accessibility API.
- **Cmd+Z as rejection signal** — undoing a conversion with Cmd+Z now also labels the training sample as `"skip"` and records the rejection, so the ML pipeline learns from it exactly like a backspace rejection.
- **Retraining trigger fix** — replaced the fragile `labeledCount % 100 == 0` check with a direct call to `OnDeviceTrainer.trainIfReady()`, which already tracks its own `lastTrainedCount`. Retraining now fires reliably every 100 new labeled samples regardless of the exact count.

---

## Requirements

- macOS 13 Ventura or later
- Accessibility permission (System Settings → Privacy & Security → Accessibility)

## Build

```bash
swift build -c release
```

The binary lands at `.build/release/SwitcherLM`. On first launch grant Accessibility access when prompted.

---

## How it works

### Conversion triggers

Words are candidates for conversion at **word boundaries**: Space, Tab, Return, most punctuation. Each candidate passes through a three-phase pipeline.

### Phase 1 — Spell Check + Context (active immediately)

```
word typed
    │
    ├─ exceptions list?            → skip
    ├─ mixed script / no letters?  → skip
    ├─ URL / email / too long?     → skip
    │
    ├─ Latin word
    │     ├─ valid English?        → skip (correct layout)
    │     └─ valid Russian (converted form)?
    │           └─ score = 1.0 → convert
    │
    └─ Cyrillic word
          ├─ valid Russian?        → skip
          └─ valid English (converted form)?
                └─ score = 1.0 → convert
```

The raw spell-check score is then modulated by two context signals:

```
combinedScore = spellScore × sessionBoost × (1 + appBias × 0.3)
```

| Signal | Source | Effect |
|---|---|---|
| `spellScore` | NSSpellChecker (EN + RU) | 1.0 confident / 0.6 weak / 0.0 don't convert |
| `sessionBoost` | NLLanguageRecognizer on recent words | 0.5–1.5× — suppresses or promotes based on surrounding language |
| `appBias` | per-app history | ±30% — Terminal leans EN, Notes leans RU |

If `combinedScore > threshold` (default 0.5, adjustable in Settings) → the word is replaced.

### Phase 2 — Feature Collection (always running)

Every conversion decision records a `ConversionSample` with six features:

| Feature | Description |
|---|---|
| `ruConf` / `enConf` | Confidence of NLLanguageRecognizer on the recent buffer |
| `appBias` | Per-app EN/RU conversion ratio at decision time |
| `spellEn` / `spellRu` | Spell-check validity of original and converted form |
| `wasLatin` | Direction of the potential conversion |

The sample gets a label (`"convert"` or `"skip"`) when the user accepts or rejects the replacement. Unlabeled samples (words that were never proposed) are not used for training.

### Phase 3 — On-Device ML (activates at ≥ 200 labeled samples)

Once enough feedback has been collected, `OnDeviceTrainer` trains an `MLBoostedTreeClassifier` on a background thread:

```
labeledSamples → CSV → MLDataTable
    → MLBoostedTreeClassifier(trainingData:targetColumn:"label")
    → .mlmodel → MLModel.compileModel → .mlmodelc
    → CoreMLPredictor replaces Phase 1 logic
```

Retraining triggers every additional 100 labeled samples. The compiled model is persisted in `~/Library/Application Support/SwitcherLM/SwitcherLM.mlmodelc` and reloaded on next launch — no retraining needed at startup.

During inference the predictor is only authoritative at `confidence > 0.7`. Below that threshold the app falls back to Phase 1, so the model never makes reckless decisions on ambiguous inputs.

---

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| Double Left Shift | Force-convert selected text (or current word) |
| Cmd+Z (within 5 s of replacement) | Undo last auto-conversion (also labels sample as rejected) |
| ← Arrow (within 5 s of replacement) | Undo last auto-conversion |
| → Arrow (before word boundary) | Skip auto-conversion for the next word |

---

## Persisted data

All data files live in `~/Library/Application Support/SwitcherLM/`:

| File | Contents |
|---|---|
| `rejections.json` | Per-word rejection counts (auto-exception threshold) |
| `app_memory.json` | Per-app EN/RU conversion statistics |
| `samples.json` | Ring buffer of up to 5 000 ConversionSamples |
| `SwitcherLM.mlmodel` | Last trained CoreML source model |
| `SwitcherLM.mlmodelc` | Compiled CoreML bundle used for inference |

---

## Settings

Open via menu-bar icon → Settings…

| Setting | Default | Description |
|---|---|---|
| Auto-convert | On | Enable/disable word-boundary conversion |
| Double-Shift force convert | On | Enable/disable the Double-LShift shortcut |
| Single-letter smart convert | On | Convert single-letter layout mistakes (e.g. `ш` → `i`) |
| Skip URLs and email | On | Don't convert tokens that look like URLs, emails, paths |
| Screen flash on conversion | On | Brief translucent red/blue full-screen pulse on every auto-conversion |
| Show words in toast | On | Display `"EN  word → converted"` in the toast instead of just the language badge |
| Rejection threshold | 3 | Rejections before a word is auto-added to exceptions |
| Max word length | 40 | Longer tokens are never converted |
| **Conversion threshold** | 0.5 | Phase 1 sensitivity: 0.1 Aggressive → 0.9 Conservative |
| English / Russian layout | System | Override which input source is used per language |

The threshold slider shows the current mode:
- **Aggressive** (< 0.35) — converts on weak signals; fewer missed conversions, more false positives
- **Balanced** (0.35–0.65) — matches pre-ML behaviour
- **Conservative** (> 0.65) — only converts when the spell checker is highly confident

---

## Architecture

```
AppDelegate
    │
    ├─ KeyboardMonitor        CGEvent tap on main thread
    │       shouldConvert → decideConversion(for:)
    │       onReplace / onConversionRejected
    │
    ├─ SpellCheckService      NSSpellChecker wrapper, 500-entry LRU cache
    ├─ LayoutConverter        Mechanical EN↔RU key-position mapping
    ├─ TextReplacer           CGEventKeyboardSetUnicodeString injection
    │
    ├─ ContextLanguageTracker NLLanguageRecognizer, 400-char rolling buffer
    ├─ AppLanguageMemory      Per-bundleID EN/RU statistics
    ├─ AppFilterManager       Bundle ID blacklist (skip conversion in specified apps)
    │
    ├─ LayoutToastPresenter   Corner badge + conversion word-pair toast
    ├─ ScreenFlasher          Full-screen translucent color overlay on conversion
    │
    ├─ SampleStore            5 000-sample ring buffer, labeled by feedback
    ├─ OnDeviceTrainer        CreateML training on background thread
    └─ CoreMLPredictor        MLModel inference, confidence-gated
```

Key design constraints:
- **No clipboard for auto-convert.** Text is injected via `CGEventKeyboardSetUnicodeString`, leaving the clipboard untouched. Force-convert (selection) uses the clipboard but restores the previous contents.
- **Re-entrancy guard.** Injected events carry a `userData` marker so the event tap ignores its own keystrokes. An `isReplacing` flag provides a second layer of protection.
- **Main-thread everything.** The event tap, all service calls, and ML inference run on the main thread. Only CoreML training and sample file I/O are dispatched to background queues.

---

## Supported languages

English ↔ Russian only. The layout mapping is hardcoded in `Layouts.json` and covers standard QWERTY ↔ ЙЦУКЕН pairs including case and common punctuation.

---

## Known edge cases

- **Hyphenated Russian words** (e.g. `по-английски`) may trigger false positives because NSSpellChecker does not always recognise them as valid Russian. After 2–3 rejections the word is auto-added to exceptions.
- **Technical / rare vocabulary** not in NSSpellChecker's Russian dictionary follows the same path. The on-device model corrects these over time as it sees your rejection feedback.
- **Very fast typing** — if multiple words arrive before the async 50 ms injection completes, the `isReplacing` flag suppresses them. This is intentional.

---

## License

MIT
