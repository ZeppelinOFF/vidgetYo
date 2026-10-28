import AppKit
import SwiftUI

@MainActor
final class DesktopWidgetController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var panel: DesktopPanel?
    private var settingsWindow: NSWindow?

    init(model: AppModel) {
        self.model = model
        super.init()
    }

    func show() {
        let panel = ensurePanel()
        applyLevel()
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
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
        let hosting = NSHostingView(rootView: root)
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
        window.title = "Настройки задач"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 480, height: 520))
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
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
