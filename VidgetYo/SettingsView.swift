import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        SettingsForm(model: model)
    }
}

private struct SettingsForm: View {
    @Bindable var model: AppModel
    @State private var connectMessage: String?

    var body: some View {
        Form {
            Section("Веб-приложение") {
                TextField("Адрес API задач", text: $model.tasksURL, prompt: Text("https://example.com/api/tasks"))
                    .textFieldStyle(.roundedBorder)
                SecureField("Токен, если нужен", text: $model.token)
                    .textFieldStyle(.roundedBorder)
                TextField("Страница приложения", text: $model.appURL, prompt: Text("https://example.com"))
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Подключить") {
                        Task {
                            await model.refresh()
                            connectMessage = model.lastError ?? "Список обновлён"
                        }
                    }
                    .disabled(model.endpoint == nil)
                    if let appURL = URL(string: model.appURL), appURL.scheme == "https" || appURL.scheme == "http" {
                        Button("Открыть сайт") {
                            model.openApp()
                        }
                    }
                    Spacer()
                }
                if let connectMessage {
                    Text(connectMessage)
                        .font(.caption)
                        .foregroundStyle(model.lastError == nil ? .secondary : Color.orange)
                }
            }

            Section("Виджет") {
                Stepper(value: $model.refreshSeconds, in: 15...600, step: 15) {
                    Text("Обновлять каждые \(model.refreshSeconds) с")
                }
                Toggle("Показывать выполненные", isOn: $model.showCompleted)
                Toggle("Поверх всех окон", isOn: $model.floatAboveWindows)
                Text("Выключенный переключатель оставляет виджет на рабочем столе: он виден на обоях и на всех пространствах, обычные окна его закрывают.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Контракт API") {
                Text("GET адрес — список. POST {\"title\"} — новая задача. PATCH адрес/{id} {\"done\": true} — отметка. Если токен заполнен, уходит заголовок Authorization: Bearer.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .padding(12)
        .frame(width: 480, height: 520)
    }
}
