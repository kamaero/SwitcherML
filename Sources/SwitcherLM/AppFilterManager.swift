import AppKit

/// Persists a set of bundle IDs in which SwitcherLM should not auto-convert.
final class AppFilterManager {

    private let key = "SwitcherLM_AppBlacklist"

    private(set) var blacklist: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(blacklist), forKey: key)
        }
    }

    init() {
        let saved = UserDefaults.standard.stringArray(forKey: key) ?? []
        self.blacklist = Set(saved)
    }

    func block(_ bundleID: String) {
        blacklist.insert(bundleID)
    }

    func unblock(_ bundleID: String) {
        blacklist.remove(bundleID)
    }

    func isBlocked(_ bundleID: String) -> Bool {
        blacklist.contains(bundleID)
    }
}

// MARK: - Window Controller

final class AppFilterWindowController: NSObject, NSWindowDelegate,
                                       NSTableViewDataSource, NSTableViewDelegate {

    private var window: NSWindow?
    private var tableView: NSTableView?
    private var sortedEntries: [(id: String, name: String)] = []
    private let manager: AppFilterManager

    init(manager: AppFilterManager) {
        self.manager = manager
        super.init()
    }

    func showWindow() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 440),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        w.title = "SwitcherLM — Фильтры приложений"
        w.center()
        w.delegate = self
        w.isReleasedWhenClosed = false

        let contentView = NSView(frame: w.contentView!.bounds)
        contentView.autoresizingMask = [.width, .height]

        let info = NSTextField(labelWithString: "SwitcherLM не работает в этих приложениях:")
        info.frame = NSRect(x: 20, y: 405, width: 420, height: 20)
        info.autoresizingMask = [.width, .minYMargin]
        contentView.addSubview(info)

        let scrollView = NSScrollView(frame: NSRect(x: 20, y: 60, width: 420, height: 335))
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true

        let table = NSTableView()
        let nameCol = NSTableColumn(identifier: .init("name"))
        nameCol.title = "Приложение"
        nameCol.width = 180
        let idCol = NSTableColumn(identifier: .init("id"))
        idCol.title = "Bundle ID"
        idCol.width = 230
        table.addTableColumn(nameCol)
        table.addTableColumn(idCol)
        table.dataSource = self
        table.delegate = self
        self.tableView = table
        scrollView.documentView = table
        contentView.addSubview(scrollView)

        let addCurrentButton = NSButton(frame: NSRect(x: 20, y: 20, width: 170, height: 30))
        addCurrentButton.title = "Добавить приложение…"
        addCurrentButton.bezelStyle = .rounded
        addCurrentButton.target = self
        addCurrentButton.action = #selector(addApp)
        contentView.addSubview(addCurrentButton)

        let removeButton = NSButton(frame: NSRect(x: 200, y: 20, width: 100, height: 30))
        removeButton.title = "Удалить"
        removeButton.bezelStyle = .rounded
        removeButton.target = self
        removeButton.action = #selector(removeApp)
        contentView.addSubview(removeButton)

        w.contentView = contentView
        self.window = w
        reloadData()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func reloadData() {
        let running = NSWorkspace.shared.runningApplications
        let nameByID: [String: String] = Dictionary(uniqueKeysWithValues: running.compactMap { app in
            guard let id = app.bundleIdentifier, let name = app.localizedName else { return nil }
            return (id, name)
        })
        sortedEntries = manager.blacklist.sorted().map { id in
            let name = nameByID[id] ?? resolvedName(for: id)
            return (id: id, name: name)
        }
        tableView?.reloadData()
    }

    private func resolvedName(for bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
           let bundle = Bundle(url: url),
           let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName")
                       ?? bundle.object(forInfoDictionaryKey: "CFBundleName")) as? String {
            return name
        }
        return bundleID.components(separatedBy: ".").last ?? bundleID
    }

    @objc private func addApp() {
        let selfPID = NSRunningApplication.current.processIdentifier
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != selfPID }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }

        let alert = NSAlert()
        alert.messageText = "Добавить приложение в фильтр"
        alert.informativeText = "SwitcherLM не будет работать в выбранном приложении."
        alert.addButton(withTitle: "Добавить")
        alert.addButton(withTitle: "Отмена")

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 340, height: 26))
        for app in apps {
            if let id = app.bundleIdentifier, let name = app.localizedName {
                popup.addItem(withTitle: "\(name)   (\(id))")
                popup.lastItem?.representedObject = id
            }
        }
        alert.accessoryView = popup

        if alert.runModal() == .alertFirstButtonReturn,
           let bundleID = popup.selectedItem?.representedObject as? String {
            manager.block(bundleID)
            reloadData()
        }
    }

    @objc private func removeApp() {
        let row = tableView?.selectedRow ?? -1
        guard row >= 0, row < sortedEntries.count else { return }
        manager.unblock(sortedEntries[row].id)
        reloadData()
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int { sortedEntries.count }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        let entry = sortedEntries[row]
        switch tableColumn?.identifier.rawValue {
        case "name": return entry.name
        case "id":   return entry.id
        default:     return nil
        }
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) { window = nil }
}
