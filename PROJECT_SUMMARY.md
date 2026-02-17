# SwitcherLM — Project Summary

macOS menu bar app (Swift, SPM) that auto-corrects words typed in the wrong keyboard layout (Ru<->En).
Example: `ghbdtn` + space -> `привет`, `руддщ` + space -> `hello`.

## Architecture

```
Sources/SwitcherLM/
  main.swift                    — Entry point (NSApplication + AppDelegate)
  AppDelegate.swift             — Orchestrates all services, wires callbacks
  StatusBarController.swift     — Menu bar icon + menu (Enabled, Exceptions, Stats, Quit)
  KeyboardMonitor.swift         — CGEvent tap: buffers keystrokes, detects word boundaries,
                                  double-LShift, backspace rejection tracking
  LayoutConverter.swift         — Static char-by-char QWERTY<->ЙЦУКЕН mapping (lower+upper)
  SpellCheckService.swift       — NSSpellChecker wrapper: checks EN/RU validity, suggests conversion
  TextReplacer.swift            — Deletes chars via backspace CGEvents, pastes via Cmd+V
  InputSourceSwitcher.swift     — Switches macOS input source (TISSelectInputSource) after conversion
  MLService.swift               — Tracks rejection counts per word, auto-adds exceptions after N rejections
  ExceptionsWindowController.swift — NSWindow + NSTableView for managing exception words (UserDefaults)
```

## Core Flow

1. `KeyboardMonitor` intercepts keyDown + flagsChanged via CGEvent tap
2. Characters accumulate in `currentWord` buffer
3. On word boundary (space, enter, tab, punctuation):
   - `SpellCheckService.suggestConversion()` checks if word is misspelled in its detected language
   - If misspelled, converts to opposite layout and checks that language's dictionary
   - If converted word is valid -> replace
   - Single-char words are skipped (too ambiguous, e.g. I↔Ш) — use double-LShift instead
4. `TextReplacer` deletes old text (backspace events) and pastes new text (clipboard + Cmd+V)
5. `InputSourceSwitcher` switches macOS keyboard layout to match the target language
6. **Event suppression**: when conversion happens, the boundary event (space/punctuation) is
   suppressed (callback returns nil) and included in the paste text instead. This prevents
   the first character of the original surviving due to race condition.

## Learning Mechanism

- When user backspaces a converted word and retypes the original, `KeyboardMonitor` detects this
- `MLService` counts rejections per word
- After 3 rejections, word is auto-added to exceptions list
- Rejection data persists in `~/Library/Application Support/SwitcherLM/rejections.json`

## Double-LShift Force Conversion

- Double-tap Left Shift (within 350ms)
- If text is selected: copies selection, converts, pastes back
- If no selection: converts the last typed word in-place

## Build & Install

```bash
./scripts/install.sh            # Release build + install to /Applications
./scripts/install.sh --debug    # Debug build
```

App MUST run from /Applications for Accessibility permissions to work.

## Key Dependencies

- Cocoa (NSSpellChecker, NSPasteboard, NSStatusBar)
- Carbon (CGEvent, TISInputSource, key codes)
- No third-party dependencies
