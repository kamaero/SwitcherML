import AppKit

/// Manages a list of words that should not be auto-corrected.
final class ExceptionsManager {

    private let key = "SwitcherLM_Exceptions"

    var exceptions: Set<String> {
        didSet {
            let array = Array(exceptions)
            UserDefaults.standard.set(array, forKey: key)
        }
    }

    init() {
        let saved = UserDefaults.standard.stringArray(forKey: key) ?? []
        self.exceptions = Set(saved)
    }

    func add(_ word: String) {
        exceptions.insert(word.lowercased())
    }

    func remove(_ word: String) {
        exceptions.remove(word.lowercased())
    }

    func contains(_ word: String) -> Bool {
        exceptions.contains(word.lowercased())
    }
}

/// Window controller for managing exception words.
final class ExceptionsWindowController: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {

    private var window: NSWindow?
    private var tableView: NSTableView?
    private var sortedExceptions: [String] = []
    private let manager: ExceptionsManager

    init(manager: ExceptionsManager) {
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
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 500),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        w.title = "SwitcherLM — Exceptions"
        w.center()
        w.delegate = self
        w.isReleasedWhenClosed = false

        let contentView = NSView(frame: w.contentView!.bounds)
        contentView.autoresizingMask = [.width, .height]

        // Scroll view with table
        let scrollView = NSScrollView(frame: NSRect(x: 20, y: 60, width: 360, height: 420))
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true

        let table = NSTableView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("word"))
        column.title = "Word"
        column.width = 340
        table.addTableColumn(column)
        table.dataSource = self
        table.delegate = self
        self.tableView = table

        scrollView.documentView = table
        contentView.addSubview(scrollView)

        // Add button
        let addButton = NSButton(frame: NSRect(x: 20, y: 20, width: 80, height: 30))
        addButton.title = "Add..."
        addButton.bezelStyle = .rounded
        addButton.target = self
        addButton.action = #selector(addException)
        contentView.addSubview(addButton)

        // Remove button
        let removeButton = NSButton(frame: NSRect(x: 110, y: 20, width: 80, height: 30))
        removeButton.title = "Remove"
        removeButton.bezelStyle = .rounded
        removeButton.target = self
        removeButton.action = #selector(removeException)
        contentView.addSubview(removeButton)

        w.contentView = contentView
        self.window = w
        reloadData()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func reloadData() {
        sortedExceptions = manager.exceptions.sorted()
        tableView?.reloadData()
    }

    @objc private func addException() {
        let alert = NSAlert()
        alert.messageText = "Add Exception"
        alert.informativeText = "Enter a word that should never be auto-corrected:"
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 250, height: 24))
        alert.accessoryView = input

        if alert.runModal() == .alertFirstButtonReturn {
            let word = input.stringValue.trimmingCharacters(in: .whitespaces)
            if !word.isEmpty {
                manager.add(word)
                reloadData()
            }
        }
    }

    @objc private func removeException() {
        let row = tableView?.selectedRow ?? -1
        guard row >= 0, row < sortedExceptions.count else { return }
        manager.remove(sortedExceptions[row])
        reloadData()
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        sortedExceptions.count
    }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        sortedExceptions[row]
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
