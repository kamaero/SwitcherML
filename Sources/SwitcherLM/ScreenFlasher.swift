import AppKit

/// Briefly flashes all screens with a translucent color overlay to signal an auto-conversion.
/// Red = switched to English, Blue = switched to Russian.
final class ScreenFlasher {

    private let settings = SettingsManager.shared
    private var windows: [NSWindow] = []

    func flash(language: InputSourceSwitcher.Language) {
        guard settings.screenFlashEnabled else { return }

        let color: NSColor
        switch language {
        case .english: color = .systemRed
        case .russian: color = .systemBlue
        case .unknown: return
        }

        hideAll()

        for screen in NSScreen.screens {
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
            window.ignoresMouseEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
            window.alphaValue = 0

            let view = FlashView(frame: NSRect(origin: .zero, size: screen.frame.size), color: color)
            window.contentView = view
            windows.append(window)

            window.orderFront(nil)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.06
                window.animator().alphaValue = 1.0
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { [weak self] in
            self?.fadeOut()
        }
    }

    private func fadeOut() {
        let current = windows
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
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
}

private final class FlashView: NSView {
    private let color: NSColor

    init(frame frameRect: NSRect, color: NSColor) {
        self.color = color
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = color.withAlphaComponent(0.15).cgColor
    }

    required init?(coder: NSCoder) { fatalError() }
    override var isOpaque: Bool { false }
}
