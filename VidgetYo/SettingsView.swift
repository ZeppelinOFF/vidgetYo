import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        SettingsForm(model: model)
    }
}

private struct SettingsForm: View {
    @Bindable var model: AppModel
    @State private var mail = ""
    @State private var password = ""

    var body: some View {
        Form {
            Section("Ёжка") {
                if model.isLoggedIn {
                    LabeledContent("Аккаунт") {
                        Text(model.fullName.isEmpty ? model.mail : "\(model.fullName) · \(model.mail)")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                    Button("Выйти из аккаунта", role: .destructive) {
                        model.signOut()
                        password = ""
                    }
                } else {
                    TextField("Почта", text: $mail, prompt: Text("name@company.com"))
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.username)
                    SecureField("Пароль", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.password)
                        .onSubmit { signIn() }
                    Button(model.isSigningIn ? "Вход…" : "Войти") {
                        signIn()
                    }
                    .disabled(model.isSigningIn || mail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty)
                }
                if let lastError = model.lastError, !model.isConnected {
                    Text(lastError)
                        .font(.caption)
                        .foregroundStyle(Color.orange)
                }
            }

            if model.isLoggedIn {
                Section("Доска") {
                    Picker("Пространство", selection: workspaceSelection) {
                        Text("Не выбрано").tag(0)
                        ForEach(model.workspaces) { place in
                            Text(place.title).tag(place.id)
                        }
                    }
                    .disabled(model.isLoadingCatalog || model.workspaces.isEmpty)
                    Picker("Доска", selection: projectSelection) {
                        Text("Не выбрано").tag(0)
                        ForEach(model.projects) { place in
                            Text(place.title).tag(place.id)
                        }
                    }
                    .disabled(model.workspaceID == nil || model.isLoadingCatalog || model.projects.isEmpty)
                    Text("Сначала пространство, затем доска. Доска — это проект Ёжки.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Открыть Ёжку") {
                            model.openSite()
                        }
                        if model.isLoadingCatalog {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Spacer()
                    }
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
        }
        .formStyle(.grouped)
        .padding(12)
        .frame(width: 480)
    }

    private var workspaceSelection: Binding<Int> {
        Binding(
            get: { model.workspaceID ?? 0 },
            set: { id in
                guard id != 0, id != model.workspaceID else { return }
                Task { await model.selectWorkspace(id) }
            }
        )
    }

    private var projectSelection: Binding<Int> {
        Binding(
            get: { model.projectID ?? 0 },
            set: { id in
                guard id != 0, id != model.projectID else { return }
                Task { await model.selectProject(id) }
            }
        )
    }

    private func signIn() {
        let mail = mail
        let password = password
        self.password = ""
        Task { await model.signIn(mail: mail, password: password) }
    }
}
