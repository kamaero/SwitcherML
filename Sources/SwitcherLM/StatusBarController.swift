import AppKit

/// Manages the menu bar status item and its menu.
final class StatusBarController {

    private var statusItem: NSStatusItem!
    private var menu: NSMenu!

    private var enabledMenuItem: NSMenuItem!
    private var statsMenuItem: NSMenuItem!
    private var todayStatsMenuItem: NSMenuItem!

    var onToggleEnabled: ((Bool) -> Void)?
    var onShowExceptions: (() -> Void)?
    var onShowAppFilters: (() -> Void)?
    var onShowSettings: (() -> Void)?
    var onLayoutChanged: ((InputSourceSwitcher.Language) -> Void)?

    private(set) var isEnabled: Bool = true
    private let statsManager = StatsManager.shared
    private var layoutObserverToken: NSObjectProtocol?
    private var layoutSyncTimer: Timer?
    private var lastShownSourceID: String?

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        buildMenu()
        statusItem.menu = menu
        startLayoutTracking()
    }

    func incrementStats() {
        statsManager.recordConverted()
        updateStatsMenuItem()
    }

    func incrementRejections() {
        statsManager.recordRejected()
        updateStatsMenuItem()
    }

    /// Forces menu-bar badge refresh from the current macOS input source.
    func syncLayoutBadge() {
        refreshLayoutIfNeeded(force: true)
    }

    private func buildMenu() {
        menu = NSMenu()

        // App title
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        let titleItem = NSMenuItem(title: "SwitcherLM v\(version)", action: nil, keyEquivalent: "")
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

        // App Filters
        let filtersItem = NSMenuItem(
            title: "App Filters...",
            action: #selector(showAppFilters),
            keyEquivalent: ""
        )
        filtersItem.target = self
        menu.addItem(filtersItem)

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
        statsMenuItem = NSMenuItem(title: "Total: 0 | Rejected: 0", action: nil, keyEquivalent: "")
        statsMenuItem.isEnabled = false
        menu.addItem(statsMenuItem)

        todayStatsMenuItem = NSMenuItem(title: "Today: 0 | Rejected: 0", action: nil, keyEquivalent: "")
        todayStatsMenuItem.isEnabled = false
        menu.addItem(todayStatsMenuItem)

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

        updateStatsMenuItem()
    }

    private func updateStatsMenuItem() {
        statsMenuItem.title = "Total: \(statsManager.totalConverted) | Rejected: \(statsManager.totalRejected)"
        todayStatsMenuItem.title = "Today: \(statsManager.todayConverted) | Rejected: \(statsManager.todayRejected)"
    }

    // MARK: - Layout tracking via TIS notification

    private func startLayoutTracking() {
        layoutObserverToken = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.Carbon.TISNotifySelectedKeyboardInputSourceChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.layoutDidChange()
        }
        // Periodic sync is a safety net for missed/late distributed notifications.
        layoutSyncTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshLayoutIfNeeded(force: false)
        }
        refreshLayoutIfNeeded(force: true)
    }

    private func layoutDidChange() {
        refreshLayoutIfNeeded(force: true)
    }

    private func refreshLayoutIfNeeded(force: Bool) {
        let currentSourceID = InputSourceSwitcher.currentSourceID()
        if !force, currentSourceID == lastShownSourceID {
            return
        }
        lastShownSourceID = currentSourceID
        let language = InputSourceSwitcher.currentLanguage(for: currentSourceID)
        updateLayoutBadge(for: language)
        if language != .unknown {
            onLayoutChanged?(language)
        }
    }

    private func updateLayoutBadge(for language: InputSourceSwitcher.Language) {
        guard let button = statusItem.button else { return }
        let badge: (text: String, color: NSColor)
        switch language {
        case .english:
            badge = ("EN", .systemRed)
        case .russian:
            badge = ("RU", .systemBlue)
        case .unknown:
            badge = (InputSourceSwitcher.currentLayoutAbbreviation(), .systemGray)
        }
        button.image = badgeImage(text: badge.text, background: badge.color)
        button.image?.size = NSSize(width: 28, height: 16)
        button.imagePosition = .imageOnly
        button.toolTip = "SwitcherLM (\(badge.text))"
    }

    private func badgeImage(text: String, background: NSColor) -> NSImage {
        let size = NSSize(width: 28, height: 16)
        let image = NSImage(size: size)
        image.lockFocus()

        let rect = NSRect(origin: .zero, size: size)
        let rounded = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
        background.setFill()
        rounded.fill()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 10),
            .foregroundColor: NSColor.white
        ]
        let string = NSString(string: text)
        let textSize = string.size(withAttributes: attrs)
        let textRect = NSRect(
            x: (size.width - textSize.width) / 2,
            y: (size.height - textSize.height) / 2 - 0.5,
            width: textSize.width,
            height: textSize.height
        )
        string.draw(in: textRect, withAttributes: attrs)

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    @objc private func toggleEnabled() {
        isEnabled.toggle()
        enabledMenuItem.state = isEnabled ? .on : .off
        onToggleEnabled?(isEnabled)
    }

    @objc private func showExceptions() {
        onShowExceptions?()
    }

    @objc private func showAppFilters() {
        onShowAppFilters?()
    }

    @objc private func showSettings() {
        onShowSettings?()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    deinit {
        if let token = layoutObserverToken {
            DistributedNotificationCenter.default().removeObserver(token)
        }
        layoutSyncTimer?.invalidate()
    }
}
