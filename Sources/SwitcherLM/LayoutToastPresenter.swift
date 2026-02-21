import AppKit

final class LayoutToastPresenter {

    private let settings = SettingsManager.shared
    private var windows: [NSWindow] = []

    /// Show a language badge toast. If `conversion` is provided and toastShowWords is on,
    /// shows "EN  word → converted" in a single wider toast in the top-right corner.
    func show(language: InputSourceSwitcher.Language, conversion: (from: String, to: String)? = nil) {
        let style = styleFor(language: language)
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
                        ?? NSScreen.main else { return }

        hideAll()

        if let conv = conversion, settings.toastShowWords {
            showConversionToast(style: style, conversion: conv, on: screen)
        } else {
            showLanguageBadges(style: style, on: screen)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + settings.toastDuration) { [weak self] in
            self?.fadeOutAndHide()
        }
    }

    // MARK: - Private

    private func showLanguageBadges(style: (text: String, color: NSColor), on screen: NSScreen) {
        let size = NSSize(width: 76, height: 34)
        let padding: CGFloat = 18
        let frame = screen.visibleFrame
        let allCorners = cornerPoints(in: frame, size: size, padding: padding)
        let corners = selectedCorners(from: allCorners, count: settings.toastCornerCount)

        for origin in corners {
            let rect = NSRect(origin: origin, size: size)
            let view = ToastView(
                frame: NSRect(origin: .zero, size: size),
                mainText: style.text,
                subText: nil,
                color: style.color
            )
            let window = makeWindow(rect: rect, content: view)
            windows.append(window)
            window.orderFront(nil)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.08
                window.animator().alphaValue = 1.0
            }
        }
    }

    private func showConversionToast(
        style: (text: String, color: NSColor),
        conversion: (from: String, to: String),
        on screen: NSScreen
    ) {
        let truncate: (String) -> String = { s in
            s.count > 22 ? String(s.prefix(20)) + "…" : s
        }
        let convText = "\(truncate(conversion.from)) → \(truncate(conversion.to))"

        // Measure total width needed
        let badgeAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 13)]
        let convAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        ]
        let badgeWidth = (style.text as NSString).size(withAttributes: badgeAttrs).width
        let convWidth = ("  \(convText)" as NSString).size(withAttributes: convAttrs).width
        let width = badgeWidth + convWidth + 24   // 24px horizontal padding
        let size = NSSize(width: max(width, 76), height: 34)

        let padding: CGFloat = 18
        let frame = screen.visibleFrame
        let origin = NSPoint(
            x: frame.maxX - size.width - padding,
            y: frame.maxY - size.height - padding
        )
        let rect = NSRect(origin: origin, size: size)
        let view = ToastView(
            frame: NSRect(origin: .zero, size: size),
            mainText: style.text,
            subText: convText,
            color: style.color
        )
        let window = makeWindow(rect: rect, content: view)
        windows.append(window)
        window.orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.08
            window.animator().alphaValue = 1.0
        }
    }

    private func makeWindow(rect: NSRect, content: NSView) -> NSWindow {
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
        window.contentView = content
        return window
    }

    private func styleFor(language: InputSourceSwitcher.Language) -> (text: String, color: NSColor) {
        switch language {
        case .english: return ("EN", .systemRed)
        case .russian: return ("RU", .systemBlue)
        case .unknown: return ("??", .systemGray)
        }
    }

    private func cornerPoints(in frame: NSRect, size: NSSize, padding: CGFloat) -> [NSPoint] {
        [
            NSPoint(x: frame.minX + padding, y: frame.maxY - size.height - padding), // TL
            NSPoint(x: frame.maxX - size.width - padding, y: frame.maxY - size.height - padding), // TR
            NSPoint(x: frame.minX + padding, y: frame.minY + padding), // BL
            NSPoint(x: frame.maxX - size.width - padding, y: frame.minY + padding), // BR
        ]
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
        for window in windows { window.orderOut(nil) }
        windows.removeAll()
    }

    private func selectedCorners(from corners: [NSPoint], count: Int) -> [NSPoint] {
        switch count {
        case 1:  return [corners[1]]        // TR
        case 2:  return [corners[0], corners[1]] // TL + TR
        default: return corners
        }
    }
}

// MARK: - ToastView

private final class ToastView: NSView {
    private let mainText: String
    private let subText: String?
    private let color: NSColor

    init(frame frameRect: NSRect, mainText: String, subText: String?, color: NSColor) {
        self.mainText = mainText
        self.subText = subText
        self.color = color
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) { fatalError() }
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let rect = bounds

        let bg = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        color.withAlphaComponent(0.92).setFill()
        bg.fill()

        if let sub = subText {
            // Two-part: "EN" bold + "  word → converted" monospaced
            let mainAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 13),
                .foregroundColor: NSColor.white
            ]
            let subAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                .foregroundColor: NSColor.white.withAlphaComponent(0.9)
            ]
            let mainStr = mainText as NSString
            let subStr = "  \(sub)" as NSString
            let mainSize = mainStr.size(withAttributes: mainAttrs)
            let subSize  = subStr.size(withAttributes: subAttrs)
            let totalWidth = mainSize.width + subSize.width
            let startX = (rect.width - totalWidth) / 2
            let mainY = (rect.height - mainSize.height) / 2
            let subY  = (rect.height - subSize.height) / 2

            mainStr.draw(
                in: NSRect(x: startX, y: mainY, width: mainSize.width, height: mainSize.height),
                withAttributes: mainAttrs
            )
            subStr.draw(
                in: NSRect(x: startX + mainSize.width, y: subY, width: subSize.width, height: subSize.height),
                withAttributes: subAttrs
            )
        } else {
            // Original single badge layout
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 16),
                .foregroundColor: NSColor.white
            ]
            let s = mainText as NSString
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
}
