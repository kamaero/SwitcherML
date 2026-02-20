import AppKit
import ApplicationServices

final class FocusHighlighter {

    private let settings = SettingsManager.shared
    private var timer: Timer?
    private var overlayWindow: NSWindow?
    private var lastFrame: CGRect = .zero
    private var lastRole: String?

    func start() {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        timer?.tolerance = 0.1
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        hideOverlay()
    }

    private func refresh() {
        guard settings.highlightEnabled else {
            hideOverlay()
            return
        }

        guard let focused = focusedElement(),
              let role = attributeString(focused, kAXRoleAttribute as CFString),
              isTextRole(role),
              let frame = attributeFrame(focused, kAXFrameAttribute as CFString) else {
            hideOverlay()
            return
        }

        showOverlay(frame: frame, role: role)
    }

    private func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &value)
        guard result == .success else { return nil }
        guard let value else { return nil }
        if CFGetTypeID(value) != AXUIElementGetTypeID() {
            return nil
        }
        return (value as! AXUIElement)
    }

    private func attributeString(_ element: AXUIElement, _ attr: CFString) -> String? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attr, &value)
        guard result == .success else { return nil }
        return value as? String
    }

    private func attributeFrame(_ element: AXUIElement, _ attr: CFString) -> CGRect? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attr, &value)
        guard result == .success, let value else { return nil }
        if CFGetTypeID(value) != AXValueGetTypeID() {
            return nil
        }
        let axValue = (value as! AXValue)
        var rect = CGRect.zero
        AXValueGetValue(axValue, .cgRect, &rect)
        return rect
    }

    private func isTextRole(_ role: String) -> Bool {
        role == (kAXTextFieldRole as String) ||
        role == (kAXTextAreaRole as String) ||
        role == "AXSearchField"
    }

    private func showOverlay(frame: CGRect, role: String) {
        let expanded = frame.insetBy(dx: -3, dy: -3)

        if overlayWindow == nil {
            let window = NSWindow(
                contentRect: expanded,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = .statusBar
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .transient]

            let view = HighlightView(frame: expanded)
            window.contentView = view
            overlayWindow = window
        }

        if expanded != lastFrame || role != lastRole {
            overlayWindow?.setFrame(expanded, display: true)
            (overlayWindow?.contentView as? HighlightView)?.frame = expanded
            lastFrame = expanded
            lastRole = role
        }

        let color = currentHighlightColor()
        (overlayWindow?.contentView as? HighlightView)?.update(color: color)
        overlayWindow?.orderFront(nil)
    }

    private func hideOverlay() {
        overlayWindow?.orderOut(nil)
        lastFrame = .zero
        lastRole = nil
    }

    private func currentHighlightColor() -> NSColor {
        switch InputSourceSwitcher.currentLanguage() {
        case .english:
            return settings.highlightEnglishColor
        case .russian:
            return settings.highlightRussianColor
        case .unknown:
            return settings.highlightEnglishColor
        }
    }
}

private final class HighlightView: NSView {

    private let shapeLayer = CAShapeLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(shapeLayer)
        shapeLayer.fillColor = NSColor.clear.cgColor
        shapeLayer.lineWidth = 2.0
        shapeLayer.shadowOpacity = 0.8
        shapeLayer.shadowRadius = 6.0
        shapeLayer.shadowOffset = .zero
        updatePath()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        updatePath()
    }

    func update(color: NSColor) {
        shapeLayer.strokeColor = color.withAlphaComponent(0.8).cgColor
        shapeLayer.shadowColor = color.cgColor
    }

    private func updatePath() {
        let inset = bounds.insetBy(dx: 1, dy: 1)
        shapeLayer.path = CGPath(roundedRect: inset, cornerWidth: 4, cornerHeight: 4, transform: nil)
        shapeLayer.frame = bounds
    }
}
