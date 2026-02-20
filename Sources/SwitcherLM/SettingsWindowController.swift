import AppKit

final class SettingsWindowController: NSObject, NSWindowDelegate {

    private let settings = SettingsManager.shared

    private var window: NSWindow?

    private var autoConvertCheckbox: NSButton?
    private var doubleShiftCheckbox: NSButton?
    private var singleLetterCheckbox: NSButton?
    private var skipURLsCheckbox: NSButton?

    private var rejectionField: NSTextField?
    private var rejectionStepper: NSStepper?

    private var maxWordField: NSTextField?
    private var maxWordStepper: NSStepper?

    private var toastDurationField: NSTextField?
    private var toastDurationStepper: NSStepper?
    private var toastCornersPopup: NSPopUpButton?

    private var englishPopup: NSPopUpButton?
    private var russianPopup: NSPopUpButton?
    private var inputSources: [InputSourceSwitcher.InputSourceInfo] = []

    func showWindow() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        w.title = "SwitcherLM — Настройки"
        w.center()
        w.delegate = self
        w.isReleasedWhenClosed = false

        let contentView = NSView(frame: w.contentView!.bounds)
        contentView.autoresizingMask = [.width, .height]

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        let auto = checkbox(title: "Автоконвертация на границе слова", action: #selector(toggleAutoConvert))
        autoConvertCheckbox = auto
        stack.addArrangedSubview(auto)

        let doubleShift = checkbox(title: "Double-Shift: конвертировать выделение", action: #selector(toggleDoubleShift))
        doubleShiftCheckbox = doubleShift
        stack.addArrangedSubview(doubleShift)

        let singleLetter = checkbox(title: "Умная однобуквенная конвертация", action: #selector(toggleSingleLetter))
        singleLetterCheckbox = singleLetter
        stack.addArrangedSubview(singleLetter)

        let skipURLs = checkbox(title: "Пропускать URL, email и пути", action: #selector(toggleSkipURLs))
        skipURLsCheckbox = skipURLs
        stack.addArrangedSubview(skipURLs)

        stack.addArrangedSubview(label(text: "Порог отклонений (авто-исключения):"))
        let rejectionRow = stepperRow(
            min: 1,
            max: 10,
            action: #selector(changeRejectionThreshold)
        )
        rejectionField = rejectionRow.field
        rejectionStepper = rejectionRow.stepper
        stack.addArrangedSubview(rejectionRow.view)

        stack.addArrangedSubview(label(text: "Максимальная длина слова:"))
        let maxWordRow = stepperRow(
            min: 5,
            max: 80,
            action: #selector(changeMaxWordLength)
        )
        maxWordField = maxWordRow.field
        maxWordStepper = maxWordRow.stepper
        stack.addArrangedSubview(maxWordRow.view)

        stack.addArrangedSubview(label(text: "Длительность toast (сек):"))
        let toastDurationRow = stepperRow(
            min: 2,
            max: 30,
            action: #selector(changeToastDuration)
        )
        toastDurationField = toastDurationRow.field
        toastDurationStepper = toastDurationRow.stepper
        stack.addArrangedSubview(toastDurationRow.view)

        stack.addArrangedSubview(label(text: "Количество углов для toast:"))
        let cornersRow = popupRow(action: #selector(changeToastCorners))
        toastCornersPopup = cornersRow
        cornersRow.addItems(withTitles: ["1", "2", "4"])
        stack.addArrangedSubview(cornersRow)

        stack.addArrangedSubview(label(text: "Английская раскладка:"))
        let englishRow = popupRow(action: #selector(changeEnglishSource))
        englishPopup = englishRow
        stack.addArrangedSubview(englishRow)

        stack.addArrangedSubview(label(text: "Русская раскладка:"))
        let russianRow = popupRow(action: #selector(changeRussianSource))
        russianPopup = russianRow
        stack.addArrangedSubview(russianRow)

        let helpButton = NSButton(title: "Справка", target: self, action: #selector(showHelp))
        helpButton.bezelStyle = .rounded
        stack.addArrangedSubview(helpButton)

        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(stack)

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.documentView = documentView
        scrollView.drawsBackground = false

        contentView.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),

            documentView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            documentView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            documentView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            documentView.bottomAnchor.constraint(equalTo: scrollView.contentView.bottomAnchor),
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),

            stack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: documentView.bottomAnchor, constant: -8),
        ])

        w.contentView = contentView
        self.window = w

        syncFromSettings()

        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func checkbox(title: String, action: Selector) -> NSButton {
        let button = NSButton(checkboxWithTitle: title, target: self, action: action)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    private func label(text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }

    private func stepperRow(min: Double, max: Double, action: Selector) -> (view: NSView, field: NSTextField, stepper: NSStepper) {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let field = NSTextField()
        field.isEditable = false
        field.isBezeled = true
        field.alignment = .right
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: 50).isActive = true

        let stepper = NSStepper()
        stepper.minValue = min
        stepper.maxValue = max
        stepper.increment = 1
        stepper.target = self
        stepper.action = action
        stepper.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(field)
        container.addSubview(stepper)

        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            field.topAnchor.constraint(equalTo: container.topAnchor),
            field.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            stepper.leadingAnchor.constraint(equalTo: field.trailingAnchor, constant: 8),
            stepper.centerYAnchor.constraint(equalTo: field.centerYAnchor),
            stepper.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        return (container, field, stepper)
    }

    private func popupRow(action: Selector) -> NSPopUpButton {
        let popup = NSPopUpButton()
        popup.target = self
        popup.action = action
        popup.translatesAutoresizingMaskIntoConstraints = false
        popup.widthAnchor.constraint(equalToConstant: 280).isActive = true
        return popup
    }

    private func syncFromSettings() {
        autoConvertCheckbox?.state = settings.autoConvertEnabled ? .on : .off
        doubleShiftCheckbox?.state = settings.doubleShiftEnabled ? .on : .off
        singleLetterCheckbox?.state = settings.singleLetterAutoConvert ? .on : .off
        skipURLsCheckbox?.state = settings.skipURLsAndEmail ? .on : .off

        rejectionStepper?.integerValue = settings.rejectionThreshold
        rejectionField?.stringValue = "\(settings.rejectionThreshold)"

        maxWordStepper?.integerValue = settings.maxWordLength
        maxWordField?.stringValue = "\(settings.maxWordLength)"

        let durationTenths = Int(round(settings.toastDuration * 10))
        toastDurationStepper?.integerValue = durationTenths
        toastDurationField?.stringValue = String(format: "%.1f", settings.toastDuration)

        selectToastCornerCount(settings.toastCornerCount)

        reloadInputSources()
    }

    private func selectToastCornerCount(_ value: Int) {
        let title = "\(value)"
        for item in toastCornersPopup?.itemArray ?? [] {
            if item.title == title {
                toastCornersPopup?.select(item)
                return
            }
        }
        toastCornersPopup?.selectItem(withTitle: "4")
    }

    private func reloadInputSources() {
        inputSources = InputSourceSwitcher.availableInputSources()

        let english = englishPopup
        let russian = russianPopup

        english?.removeAllItems()
        russian?.removeAllItems()

        english?.addItem(withTitle: "Системная")
        english?.lastItem?.representedObject = nil

        russian?.addItem(withTitle: "Системная")
        russian?.lastItem?.representedObject = nil

        for source in inputSources {
            english?.addItem(withTitle: source.name)
            english?.lastItem?.representedObject = source.id

            russian?.addItem(withTitle: source.name)
            russian?.lastItem?.representedObject = source.id
        }

        selectPopup(english, preferredID: settings.preferredEnglishSourceID)
        selectPopup(russian, preferredID: settings.preferredRussianSourceID)
    }

    private func selectPopup(_ popup: NSPopUpButton?, preferredID: String?) {
        guard let popup else { return }
        if let preferredID {
            for item in popup.itemArray {
                if let id = item.representedObject as? String, id == preferredID {
                    popup.select(item)
                    return
                }
            }
        }
        popup.selectItem(at: 0)
    }

    @objc private func toggleAutoConvert() {
        settings.autoConvertEnabled = autoConvertCheckbox?.state == .on
    }

    @objc private func toggleDoubleShift() {
        settings.doubleShiftEnabled = doubleShiftCheckbox?.state == .on
    }

    @objc private func toggleSingleLetter() {
        settings.singleLetterAutoConvert = singleLetterCheckbox?.state == .on
    }

    @objc private func toggleSkipURLs() {
        settings.skipURLsAndEmail = skipURLsCheckbox?.state == .on
    }

    @objc private func changeRejectionThreshold() {
        let value = rejectionStepper?.integerValue ?? settings.rejectionThreshold
        settings.rejectionThreshold = value
        rejectionField?.stringValue = "\(settings.rejectionThreshold)"
    }

    @objc private func changeMaxWordLength() {
        let value = maxWordStepper?.integerValue ?? settings.maxWordLength
        settings.maxWordLength = value
        maxWordField?.stringValue = "\(settings.maxWordLength)"
    }

    @objc private func changeToastDuration() {
        let tenths = toastDurationStepper?.integerValue ?? Int(round(settings.toastDuration * 10))
        let clamped = min(max(tenths, 2), 30)
        let seconds = Double(clamped) / 10.0
        settings.toastDuration = seconds
        toastDurationField?.stringValue = String(format: "%.1f", settings.toastDuration)
    }

    @objc private func changeToastCorners() {
        let value = Int(toastCornersPopup?.selectedItem?.title ?? "") ?? 4
        settings.toastCornerCount = value
        selectToastCornerCount(settings.toastCornerCount)
    }

    @objc private func changeEnglishSource() {
        guard let item = englishPopup?.selectedItem else { return }
        settings.preferredEnglishSourceID = item.representedObject as? String
    }

    @objc private func changeRussianSource() {
        guard let item = russianPopup?.selectedItem else { return }
        settings.preferredRussianSourceID = item.representedObject as? String
    }

    @objc private func showHelp() {
        let alert = NSAlert()
        alert.messageText = "Как пользоваться SwitcherLM"
        alert.informativeText =
        """
        • Автоконвертация срабатывает на границе слова (пробел, таб, пунктуация).
        • Double-Shift конвертирует только выделенный текст.
        • Стрелка ← отменяет последнюю замену (в течение 5 секунд).
        • Стрелка → отключает автоконвертацию для следующего слова.
        • Список исключений — через меню «Exceptions…».
        """
        alert.addButton(withTitle: "ОК")
        alert.runModal()
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
