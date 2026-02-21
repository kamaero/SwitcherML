import AppKit

final class LayoutToastPresenter {

    private let settings = SettingsManager.shared
    private var windows: [NSWindow] = []

    func show(language: InputSourceSwitcher.Language) {
        let style = styleFor(language: language)
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
                        ?? NSScreen.main else { return }

        hideAll()

        let size = NSSize(width: 76, height: 34)
        let padding: CGFloat = 18
        let frame = screen.visibleFrame
        let allCorners = [
            NSPoint(x: frame.minX + padding, y: frame.maxY - size.height - padding), // TL
            NSPoint(x: frame.maxX - size.width - padding, y: frame.maxY - size.height - padding), // TR
            NSPoint(x: frame.minX + padding, y: frame.minY + padding), // BL
            NSPoint(x: frame.maxX - size.width - padding, y: frame.minY + padding), // BR
        ]
        let corners = selectedCorners(from: allCorners, count: settings.toastCornerCount)

        for origin in corners {
            let rect = NSRect(origin: origin, size: size)
            let window = NSWindow(
                contentRect: rect,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = .statusBar
            window.ignoresMouseEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .transient]
            window.alphaValue = 0
            window.contentView = ToastView(frame: NSRect(origin: .zero, size: size), text: style.text, color: style.color)
            windows.append(window)

            window.orderFront(nil)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.08
                window.animator().alphaValue = 1.0
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + settings.toastDuration) { [weak self] in
            self?.fadeOutAndHide()
        }
    }

    private func styleFor(language: InputSourceSwitcher.Language) -> (text: String, color: NSColor) {
        switch language {
        case .english:
            return ("EN", .systemRed)
        case .russian:
            return ("RU", .systemBlue)
        case .unknown:
            return ("??", .systemGray)
        }
    }

    private func fadeOutAndHide() {
        let current = windows
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            for window in current {
                window.animator().alphaValue = 0
            }
        }, completionHandler: { [weak self] in
            self?.hideAll()
        })
    }

    private func hideAll() {
        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()
    }

    private func selectedCorners(from corners: [NSPoint], count: Int) -> [NSPoint] {
        switch count {
        case 1:
            return [corners[1]] // TR
        case 2:
            return [corners[0], corners[1]] // TL + TR
        default:
            return corners
        }
    }
}

private final class ToastView: NSView {
    private let text: String
    private let color: NSColor

    init(frame frameRect: NSRect, text: String, color: NSColor) {
        self.text = text
        self.color = color
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let rect = bounds
        let bg = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        color.withAlphaComponent(0.92).setFill()
        bg.fill()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 16),
            .foregroundColor: NSColor.white
        ]
        let s = NSString(string: text)
        let size = s.size(withAttributes: attrs)
        let drawRect = NSRect(
            x: (rect.width - size.width) / 2,
            y: (rect.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
        s.draw(in: drawRect, withAttributes: attrs)
    }
}
