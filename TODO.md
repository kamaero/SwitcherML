# SwitcherLM — TODO

## Done (v1.1.0)
- [x] Basic auto-correction Ru<->En via NSSpellChecker
- [x] CGEvent tap for global key monitoring
- [x] Menu bar UI (enable/disable, exceptions, stats)
- [x] Clipboard-based text replacement (backspace + Cmd+V)
- [x] Exceptions list with GUI (UserDefaults persistence)
- [x] Short words support (removed min length filter)
- [x] Punctuation preservation (boundary char passed through correctly)
- [x] Auto-switch keyboard layout after conversion (TISSelectInputSource)
- [x] Backspace-based learning: reject conversion 3x -> auto-exception
- [x] Double-LShift: force convert last word or selected text
- [x] Build & install script (`scripts/install.sh`)

## Backlog
- [ ] Notification/toast при автозамене (чтобы пользователь видел что произошло)
- [ ] Undo последней замены по hotkey (Ctrl+Z или кастомный)
- [ ] Поддержка других раскладок (украинская, белорусская)
- [ ] Whitelist приложений (работать только в определённых apps)
- [ ] Blacklist приложений (не работать в терминале, IDE)
- [ ] Контекстное определение языка (если предыдущие слова были русские — ожидать русский)
- [ ] Иконка в menu bar меняет цвет при срабатывании
- [ ] Экспорт/импорт исключений
- [ ] Auto-update mechanism
- [ ] Proper .app bundle с иконкой и code signing
- [ ] Настройка hotkey для force-convert (сейчас хардкод на double-LShift)
- [ ] Настройка rejection threshold (сейчас хардкод 3)
- [ ] Статистика за всё время (persist across sessions)
