import AppKit

/// Manages the menu bar status item and its menu.
final class StatusBarController {

    private var statusItem: NSStatusItem!
    private var menu: NSMenu!

    private var enabledMenuItem: NSMenuItem!
    private var statsMenuItem: NSMenuItem!

    var onToggleEnabled: ((Bool) -> Void)?
    var onShowExceptions: (() -> Void)?
    var onShowSettings: (() -> Void)?

    private(set) var isEnabled: Bool = true
    private var wordsConverted: Int = 0
    private var wordsRejected: Int = 0

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "SwitcherLM")
            button.image?.size = NSSize(width: 18, height: 18)
        }

        buildMenu()
        statusItem.menu = menu
    }

    func incrementStats() {
        wordsConverted += 1
        updateStatsMenuItem()
    }

    func incrementRejections() {
        wordsRejected += 1
        updateStatsMenuItem()
    }

    private func buildMenu() {
        menu = NSMenu()

        // App title
        let titleItem = NSMenuItem(title: "SwitcherLM v1.1.0", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        menu.addItem(.separator())

        // Enabled toggle
        enabledMenuItem = NSMenuItem(
            title: "Enabled",
            action: #selector(toggleEnabled),
            keyEquivalent: "e"
        )
        enabledMenuItem.keyEquivalentModifierMask = [.command]
        enabledMenuItem.target = self
        enabledMenuItem.state = .on
        menu.addItem(enabledMenuItem)

        menu.addItem(.separator())

        // Exceptions
        let exceptionsItem = NSMenuItem(
            title: "Exceptions...",
            action: #selector(showExceptions),
            keyEquivalent: ""
        )
        exceptionsItem.target = self
        menu.addItem(exceptionsItem)

        // Settings
        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(showSettings),
            keyEquivalent: ","
        )
        settingsItem.keyEquivalentModifierMask = [.command]
        settingsItem.target = self
        menu.addItem(settingsItem)

        // Statistics
        statsMenuItem = NSMenuItem(title: "Converted: 0 | Rejected: 0", action: nil, keyEquivalent: "")
        statsMenuItem.isEnabled = false
        menu.addItem(statsMenuItem)

        // Hint
        let hintItem = NSMenuItem(title: "⇧⇧ Double-Shift to force convert", action: nil, keyEquivalent: "")
        hintItem.isEnabled = false
        menu.addItem(hintItem)

        menu.addItem(.separator())

        // Quit
        let quitItem = NSMenuItem(
            title: "Quit SwitcherLM",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = [.command]
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func updateStatsMenuItem() {
        statsMenuItem.title = "Converted: \(wordsConverted) | Rejected: \(wordsRejected)"
    }

    @objc private func toggleEnabled() {
        isEnabled.toggle()
        enabledMenuItem.state = isEnabled ? .on : .off
        onToggleEnabled?(isEnabled)
    }

    @objc private func showExceptions() {
        onShowExceptions?()
    }

    @objc private func showSettings() {
        onShowSettings?()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
