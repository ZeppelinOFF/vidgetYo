import AppKit
import SwiftUI

@MainActor
final class DesktopWidgetController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var panel: DesktopPanel?
    private var settingsWindow: NSWindow?

    private var dragObserver: NSObjectProtocol?

    init(model: AppModel) {
        self.model = model
        super.init()
        dragObserver = NotificationCenter.default.addObserver(
            forName: .vidgetYoDragEnded,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.applyLevel()
            }
        }
    }

    func show() {
        let panel = ensurePanel()
        applyLevel()
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func fit(taskCount: Int) {
        guard let panel else { return }
        let screen = panel.screen ?? NSScreen.main
        let maxHeight = (screen?.visibleFrame.height ?? 800) - 32
        let header: CGFloat = 78
        let composer: CGFloat = 52
        let row: CGFloat = 58
        let list = taskCount == 0 ? 72 : CGFloat(taskCount) * row + 16
        let height = min(max(header + list + composer, 180), maxHeight)
        var frame = panel.frame
        let top = frame.maxY
        frame.size.height = height
        frame.origin.y = top - height
        if let visible = screen?.visibleFrame {
            if frame.minY < visible.minY {
                frame.origin.y = visible.minY + 8
            }
            if frame.maxY > visible.maxY {
                frame.origin.y = visible.maxY - frame.height - 8
            }
        }
        panel.setFrame(frame, display: true, animate: true)
        OriginStore.save(frame.origin)
    }

    func applyLevel() {
        guard let panel else { return }
        if model.floatAboveWindows {
            panel.level = .floating
        } else {
            let desktop = Int(CGWindowLevelForKey(.desktopIconWindow))
            panel.level = NSWindow.Level(rawValue: desktop + 1)
        }
    }

    func showSettings() {
        let window = ensureSettingsWindow()
        window.center()
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func ensurePanel() -> DesktopPanel {
        if let panel {
            return panel
        }
        let frame = initialFrame()
        let panel = DesktopPanel(contentRect: frame)
        panel.delegate = self
        let root = WidgetRootView().environment(model)
        let hosting = WidgetHostingView(rootView: root)
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.layer?.isOpaque = false
        panel.contentView = hosting
        self.panel = panel
        return panel
    }

    private func ensureSettingsWindow() -> NSWindow {
        if let settingsWindow {
            return settingsWindow
        }
        let host = NSHostingController(rootView: SettingsView().environment(model))
        let window = NSWindow(contentViewController: host)
        window.title = "Ёжка"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 480, height: 640))
        window.isReleasedWhenClosed = false
        settingsWindow = window
        return window
    }

    private func initialFrame() -> NSRect {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let size = NSSize(width: 320, height: 520)
        var frame = NSRect(
            x: screen.maxX - size.width - 20,
            y: screen.minY + 20,
            width: size.width,
            height: size.height
        )
        if let origin = model.savedOrigin() {
            frame.origin = origin
        }
        let visible = NSScreen.screens.contains { $0.frame.intersects(frame.insetBy(dx: 40, dy: 40)) }
        if !visible {
            frame.origin = NSPoint(x: screen.maxX - size.width - 20, y: screen.minY + 20)
        }
        return frame
    }

    nonisolated func windowDidMove(_ notification: Notification) {
        nonisolated(unsafe) let notification = notification
        MainActor.assumeIsolated {
            guard let panel = notification.object as? NSWindow else { return }
            OriginStore.save(panel.frame.origin)
        }
    }
}

final class WidgetHostingView<Content: View>: NSHostingView<Content> {
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let hit = super.hitTest(point), hit !== self, containsInteractiveView(hit) {
            super.mouseDown(with: event)
            return
        }
        guard let window else { return }
        window.level = .floating
        window.performDrag(with: event)
        NotificationCenter.default.post(name: .vidgetYoDragEnded, object: window)
    }

    private func containsInteractiveView(_ view: NSView) -> Bool {
        var current: NSView? = view
        while let candidate = current, candidate !== self {
            if candidate is NSButton || candidate is NSTextField || candidate is NSScrollView {
                return true
            }
            current = candidate.superview
        }
        return false
    }
}

final class DesktopPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovable = true
        collectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
