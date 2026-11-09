import AppKit
import SwiftUI

struct WidgetRootView: View {
    @Environment(AppModel.self) private var model
    @State private var draft = ""
    @FocusState private var draftFocused: Bool

    private var typography: WidgetTypography {
        model.widgetAppearance.typography
    }

    var body: some View {
        let appearance = model.widgetAppearance
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(typography.tertiary.opacity(0.35))
            content
            Divider().background(typography.tertiary.opacity(0.35))
            composer
        }
        .foregroundStyle(typography.primary)
        .background {
            WindowDragArea()
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .opacity(0.35 + appearance.panelOpacity * 0.65)
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(appearance.background.opacity(appearance.panelOpacity))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(typography.primary.opacity(0.16 + appearance.panelOpacity * 0.12), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onAppear { refit() }
        .onChange(of: model.visibleTasks.map(\.id)) { _, _ in refit() }
        .onChange(of: model.columnID) { _, _ in refit() }
        .onChange(of: model.showCompleted) { _, _ in refit() }
        .onChange(of: model.isConnected) { _, _ in refit() }
    }

    private var showsOnboarding: Bool {
        !model.isConnected && model.tasks.isEmpty
    }

    private func refit() {
        model.controller?.fitToContent()
    }

    private var header: some View {
        ZStack {
            WindowDragArea()
            HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.projectTitle.isEmpty ? "Ёжка" : model.projectTitle)
                    .font(.headline.weight(typography.weight))
                    .widgetReadableText(typography)
                    .lineLimit(2)
                Text(model.columnTitle.isEmpty ? "Все колонки" : model.columnTitle)
                    .font(.subheadline.weight(typography.weight))
                    .foregroundStyle(typography.secondary)
                    .widgetReadableText(typography)
                    .lineLimit(1)
                if let lastError = model.lastError {
                    Text(lastError)
                        .font(.caption)
                        .foregroundStyle(Color.orange)
                        .lineLimit(2)
                }
            }
            .allowsHitTesting(false)
            Spacer(minLength: 8)
                .allowsHitTesting(false)
            Text("\(model.openCount)")
                .font(.title2.weight(typography.weight == .regular ? .semibold : typography.weight))
                .monospacedDigit()
                .foregroundStyle(typography.secondary)
                .widgetReadableText(typography)
                .allowsHitTesting(false)
            if model.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button {
                    Task { await model.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(typography.secondary)
                }
                .buttonStyle(.plain)
                .disabled(!model.isConnected)
                .help("Обновить")
            }
            Button {
                model.presentSettings()
            } label: {
                Image(systemName: "gearshape")
                    .foregroundStyle(typography.secondary)
            }
            .buttonStyle(.plain)
            .help("Настройки")
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)
        }
    }

    private var content: some View {
        Group {
            if showsOnboarding {
                emptyState
            } else if model.visibleTasks.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.title2)
                        .foregroundStyle(typography.secondary)
                    Text(emptyListTitle)
                        .foregroundStyle(typography.secondary)
                        .widgetReadableText(typography)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: WidgetMetrics.emptyList)
            } else {
                taskList
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var taskList: some View {
        let tasks = model.visibleTasks
        let maxHeight = model.controller?.screenMaxHeight() ?? 800
        let capped = WidgetMetrics.isHeightCapped(taskCount: tasks.count, maxHeight: maxHeight)
        let stack = LazyVStack(alignment: .leading, spacing: 2) {
            ForEach(tasks) { task in
                TaskRow(task: task)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)

        return Group {
            if capped {
                ScrollView {
                    stack
                }
                .frame(height: WidgetMetrics.cappedListHeight(maxHeight: maxHeight))
            } else {
                stack
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.isLoggedIn ? "Выберите доску" : "Войдите в Ёжку")
                .font(.headline.weight(typography.weight))
                .widgetReadableText(typography)
            Text(model.isLoggedIn
                 ? "Сначала пространство, затем проект. Виджет покажет задачи этой доски."
                 : "При первом запуске нужны почта и пароль с yozhka.lukit.ru. Адрес подключения не меняется.")
                .font(.callout)
                .foregroundStyle(typography.secondary)
                .widgetReadableText(typography)
                .fixedSize(horizontal: false, vertical: true)
            Button(model.isLoggedIn ? "Выбрать доску" : "Войти") {
                model.presentSettings()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(minHeight: WidgetMetrics.onboardingList)
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField("Новая задача", text: $draft)
                .textFieldStyle(.plain)
                .foregroundStyle(typography.primary)
                .fontWeight(typography.weight)
                .widgetReadableText(typography)
                .focused($draftFocused)
                .disabled(!model.isConnected)
                .onSubmit { submit() }
            Button(action: submit) {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .disabled(!model.isConnected || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var statusLine: String {
        if let lastError = model.lastError {
            return lastError
        }
        if !model.isLoggedIn {
            return "Нет входа в Ёжку"
        }
        if model.projectID == nil {
            return model.workspaceTitle.isEmpty ? "Выберите пространство и проект" : model.workspaceTitle
        }
        if model.columnID != nil, model.visibleTasks.isEmpty, !model.tasks.isEmpty {
            return "В колонке «\(model.columnTitle)» нет задач"
        }
        if let lastUpdated = model.lastUpdated {
            let place = model.workspaceTitle.isEmpty ? "Ёжка" : model.workspaceTitle
            return "\(place) · \(lastUpdated.formatted(date: .omitted, time: .shortened))"
        }
        return model.workspaceTitle.isEmpty ? "Ёжка" : model.workspaceTitle
    }

    private var emptyListTitle: String {
        if model.tasks.isEmpty {
            return "Список пуст"
        }
        if model.columnID != nil, model.visibleTasks.isEmpty {
            return "В этой колонке пусто"
        }
        return "Все задачи выполнены"
    }

    private func submit() {
        let title = draft
        draft = ""
        Task { await model.add(title: title) }
    }
}

private struct TaskRow: View {
    @Environment(AppModel.self) private var model
    let task: TaskItem

    private var typography: WidgetTypography {
        model.widgetAppearance.typography
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Button {
                model.toggle(task)
            } label: {
                Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.done ? Color.accentColor : typography.secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help(task.done ? "Вернуть в работу" : "Отметить выполненной")

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.body.weight(typography.weight))
                    .strikethrough(task.done)
                    .foregroundStyle(task.done ? typography.secondary : typography.primary)
                    .widgetReadableText(typography)
                    .lineLimit(2)
                if let caption = taskCaption(task) {
                    Text(caption.text)
                        .font(.caption.weight(typography.weight))
                        .foregroundStyle(caption.overdue && !task.done ? Color.orange : typography.secondary)
                        .widgetReadableText(typography)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                model.open(task)
            }

            if task.url != nil {
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(typography.tertiary)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.001))
        }
    }
}

private func taskCaption(_ task: TaskItem) -> DueLabel.Value? {
    let due = DueLabel.make(task.due)
    let status = task.status?.trimmingCharacters(in: .whitespacesAndNewlines)
    switch (status?.isEmpty == false ? status : nil, due) {
    case let (status?, due?):
        return DueLabel.Value(text: "\(status) · \(due.text)", overdue: due.overdue)
    case let (status?, nil):
        return DueLabel.Value(text: status, overdue: false)
    case let (nil, due?):
        return due
    case (nil, nil):
        return nil
    }
}

private enum DueLabel {
    struct Value {
        var text: String
        var overdue: Bool
    }

    static func make(_ raw: String?) -> Value? {
        guard let raw, !raw.isEmpty else { return nil }
        let day = DateFormatter()
        day.calendar = Calendar(identifier: .iso8601)
        day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = TimeZone.current
        day.dateFormat = "yyyy-MM-dd"
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withFullDate]
        guard let date = day.date(from: String(raw.prefix(10))) ?? iso.date(from: raw) else {
            return Value(text: raw, overdue: false)
        }
        let output = DateFormatter()
        output.locale = Locale(identifier: "ru_RU")
        output.setLocalizedDateFormatFromTemplate("dMMM")
        let overdue = date < Calendar.current.startOfDay(for: Date())
        return Value(text: output.string(from: date), overdue: overdue)
    }
}

extension Notification.Name {
    static let vidgetYoDragEnded = Notification.Name("vidgetyo.dragEnded")
}

struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        DragView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

final class DragView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        window.level = .floating
        window.performDrag(with: event)
        NotificationCenter.default.post(name: .vidgetYoDragEnded, object: window)
    }
}
