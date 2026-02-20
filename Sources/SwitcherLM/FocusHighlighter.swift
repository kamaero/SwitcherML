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
              let frame = attributeFrame(focused) else {
            hideOverlay()
            return
        }

        showOverlay(frame: frame.integral, role: role)
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

    private func attributeFrame(_ element: AXUIElement) -> CGRect? {
        if let frame = attributeCGRect(element, "AXFrame" as CFString) {
            return frame
        }
        guard let position = attributePoint(element, kAXPositionAttribute as CFString),
              let size = attributeSize(element, kAXSizeAttribute as CFString) else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    private func attributeCGRect(_ element: AXUIElement, _ attr: CFString) -> CGRect? {
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

    private func attributePoint(_ element: AXUIElement, _ attr: CFString) -> CGPoint? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attr, &value)
        guard result == .success, let value else { return nil }
        if CFGetTypeID(value) != AXValueGetTypeID() {
            return nil
        }
        let axValue = (value as! AXValue)
        var point = CGPoint.zero
        AXValueGetValue(axValue, .cgPoint, &point)
        return point
    }

    private func attributeSize(_ element: AXUIElement, _ attr: CFString) -> CGSize? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attr, &value)
        guard result == .success, let value else { return nil }
        if CFGetTypeID(value) != AXValueGetTypeID() {
            return nil
        }
        let axValue = (value as! AXValue)
        var size = CGSize.zero
        AXValueGetValue(axValue, .cgSize, &size)
        return size
    }

    private func isTextRole(_ role: String) -> Bool {
        role == (kAXTextFieldRole as String) ||
        role == (kAXTextAreaRole as String) ||
        role == "AXSearchField"
    }

    private func showOverlay(frame: CGRect, role: String) {
        let snapped = frame.integral

        if overlayWindow == nil {
            let window = NSWindow(
                contentRect: snapped,
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

            let view = HighlightView(frame: NSRect(origin: .zero, size: snapped.size))
            window.contentView = view
            overlayWindow = window
        }

        if snapped != lastFrame || role != lastRole {
            overlayWindow?.setFrame(snapped, display: true)
            (overlayWindow?.contentView as? HighlightView)?.frame = NSRect(origin: .zero, size: snapped.size)
            lastFrame = snapped
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
    private var strokeColor: NSColor = .systemBlue

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool {
        false
    }

    func update(color: NSColor) {
        strokeColor = color
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.clear.setFill()
        dirtyRect.fill()

        let rect = bounds.insetBy(dx: 1.5, dy: 1.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
        path.lineWidth = 2.0

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = strokeColor.withAlphaComponent(0.55)
        shadow.shadowBlurRadius = 3
        shadow.shadowOffset = .zero
        shadow.set()
        strokeColor.withAlphaComponent(0.9).setStroke()
        path.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }
}
