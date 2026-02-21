# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Build (release)
swift build -c release

# Run directly
.build/release/SwitcherLM

# Build + install to /Applications + launch
./scripts/install.sh

# Build + create .pkg installer → dist/
./scripts/package.sh

# Sync version from git history to Info.plist
./scripts/sync-version.sh

# Run tests
swift test
```

## Architecture

**SwitcherLM** is a zero-dependency macOS menu-bar app (LSUIElement) that detects and auto-corrects keyboard layout mistakes (EN↔RU) in real time using a three-phase ML pipeline.

### Three-Phase Decision Pipeline

```
Phase 1 (always):   NSSpellChecker + NLLanguageRecognizer context + per-app bias
Phase 2 (always):   Passive collection of ConversionSample (6 features) into ring buffer
Phase 3 (≥200 samples): MLBoostedTreeClassifier — overrides Phase 1 only if confidence > 0.7
```

All phases run on the **main thread**. Only CoreML training (`OnDeviceTrainer`) dispatches to a background queue.

### Component Map

```
AppDelegate (orchestrator)
 ├── KeyboardMonitor        CGEvent tap; accumulates currentWord; fires callbacks on boundaries
 ├── SpellCheckService      NSSpellChecker wrapper with 500-entry LRU cache
 ├── LayoutConverter        Char-by-char map (Layouts.json), case-preserving, EN↔RU
 ├── TextReplacer           Injects text via CGEventKeyboardSetUnicodeString (no clipboard)
 ├── InputSourceSwitcher    TISSelectInputSource wrapper; switches layout after conversion
 ├── ContextLanguageTracker 400-char rolling buffer → 0.5–1.5× sessionBoost via NLLanguageRecognizer
 ├── AppLanguageMemory      Per-bundleID EN/RU ratio → [-1, +1] appBias
 ├── SampleStore            5 000-sample ring buffer; evicts oldest unlabeled first
 ├── OnDeviceTrainer        CreateML training on bg thread; fires onModelReady on main
 ├── CoreMLPredictor        Inference on compiled .mlmodelc; returns (label, confidence)
 ├── MLService              Tracks rejection counts → auto-exception after N rejections
 ├── ExceptionsManager      Set<String> backed by UserDefaults
 ├── SettingsManager        Singleton; UserDefaults; posts didChangeNotification on any write
 ├── StatsManager           Session + daily stats (UserDefaults + JSON)
 ├── StatusBarController    Menu bar icon + badge (EN/RU) + menu
 ├── LayoutToastPresenter   Fade-in/out corner notifications
 └── SettingsWindowController / ExceptionsWindowController — settings & exceptions UI
```

### Keystroke Lifecycle

1. `CGEvent tap` → `KeyboardMonitor.handleKeyEvent()` — appends char to `currentWord`
2. Word boundary (Space/Tab/Return/punctuation) → `processCurrentWord()` → `shouldConvert` callback
3. `AppDelegate.decideConversion()`: computes `combinedScore = spellScore × sessionBoost × (1 + appBias × 0.3)`, records `ConversionSample`
4. Phase 3 (if model loaded & confidence > 0.7): use prediction; else Phase 1: `SpellCheckService.suggestConversion()`
5. Conversion accepted → `TextReplacer` injects replacement + boundary; `InputSourceSwitcher` switches layout; sample labeled `"convert"`; boundary event suppressed
6. User backspaces away conversion → `MLService` increments rejection count; sample labeled `"skip"`; at `rejectionThreshold` → auto-added to `ExceptionsManager`
7. Every 100 new labeled samples → `OnDeviceTrainer.trainIfReady()` on bg thread

### Re-entrancy Guard

Injected events carry `userData = 0x53574C4D` (`EventMarker.userData`). `KeyboardMonitor` skips events with this marker. Additionally, `AppDelegate.isReplacing` flag (300 ms timeout) provides a fallback guard.

### Persistence

| Layer | What | Where |
|-------|------|--------|
| UserDefaults | Settings, exceptions, stats totals | Synchronous |
| JSON (2s debounce) | `rejections.json`, `app_memory.json` | `~/Library/Application Support/SwitcherLM/` |
| JSON (5s debounce) | `samples.json` (ring buffer) | same |
| CoreML | `SwitcherLM.mlmodel` + `.mlmodelc` | same |

### Key Design Decisions

- **No clipboard for auto-convert**: `TextReplacer` uses `CGEventKeyboardSetUnicodeString` to preserve the user's clipboard. Force-convert (Double-LShift on selection) uses clipboard but restores it after 300 ms.
- **Main thread only**: All conversion logic runs on main thread for simplicity. Only CoreML training is background.
- **Graceful degradation**: Phase 3 is optional — app is fully functional from first launch using Phase 1 only.
- **Confidence gate at 0.7**: When CoreML is uncertain, falls back to Phase 1 rather than making a bad prediction.
- **Ring buffer eviction**: Oldest *unlabeled* samples are evicted first to preserve user-labeled training data.

## Adding New Source Files

All Swift source files in `Sources/SwitcherLM/` are compiled automatically by SPM — no manifest changes needed. `Layouts.json` must be copied to the app bundle manually (see `scripts/install.sh`).

## Testing

Three XCTest files in `Tests/SwitcherLMTests/`:
- `LayoutConverterTests.swift` — conversion correctness and case preservation
- `HeuristicsTests.swift` — mixed-script, URL, email detection
- `SettingsStatsTests.swift` — default values and persistence

Run with `swift test`. Tests do not require Accessibility permissions.

## Settings Keys

All `UserDefaults` keys are prefixed `SwitcherLM_`. Defined in `SettingsManager.swift`. `SettingsManager.didChangeNotification` is broadcast on every write — UI components observe this to stay in sync.
