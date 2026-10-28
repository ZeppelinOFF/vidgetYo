import AppKit
import SwiftUI

@main
struct VidgetYoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environment(appDelegate.model)
        } label: {
            Label("Задачи", systemImage: "checklist")
        }
        .menuBarExtraStyle(.menu)
    }
}

struct MenuContent: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button(model.widgetVisible ? "Скрыть виджет" : "Показать виджет") {
            model.widgetVisible.toggle()
        }
        Button(model.floatAboveWindows ? "Закрепить на рабочем столе" : "Поверх окон") {
            model.floatAboveWindows.toggle()
        }
        Divider()
        Button("Обновить") {
            Task { await model.refresh() }
        }
        .disabled(!model.isConnected)
        Button("Настройки…") {
            model.presentSettings()
        }
        Divider()
        Button("Выйти") {
            NSApp.terminate(nil)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var widgets: DesktopWidgetController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let widgets = DesktopWidgetController(model: model)
        self.widgets = widgets
        model.controller = widgets
        model.presentSettings = { [weak widgets] in
            widgets?.showSettings()
        }
        if model.widgetVisible {
            widgets.show()
        }
        model.start()
        if !model.isConnected {
            widgets.showSettings()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
