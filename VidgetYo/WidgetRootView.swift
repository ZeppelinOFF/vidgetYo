import AppKit
import SwiftUI

struct WidgetRootView: View {
    @Environment(AppModel.self) private var model
    @State private var draft = ""
    @FocusState private var draftFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.35)
            content
            Divider().opacity(0.35)
            composer
        }
        .background {
            WindowDragArea()
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.2), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Задачи")
                    .font(.headline)
                Text(statusLine)
                    .font(.caption)
                    .foregroundStyle(model.lastError == nil ? .secondary : Color.orange)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Text("\(model.openCount)")
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            if model.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button {
                    Task { await model.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .disabled(model.endpoint == nil)
                .help("Обновить")
            }
            Button {
                model.presentSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .help("Настройки")
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var content: some View {
        Group {
            if model.endpoint == nil && model.tasks.isEmpty {
                emptyState
            } else if model.visibleTasks.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text(model.tasks.isEmpty ? "Список пуст" : "Все задачи выполнены")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(model.visibleTasks) { task in
                            TaskRow(task: task)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Подключите веб-приложение")
                .font(.headline)
            Text("Виджет читает задачи по адресу API и отмечает их выполненными на сервере.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Указать адрес") {
                model.presentSettings()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField("Новая задача", text: $draft)
                .textFieldStyle(.plain)
                .focused($draftFocused)
                .disabled(model.endpoint == nil)
                .onSubmit { submit() }
            Button(action: submit) {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .disabled(model.endpoint == nil || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var statusLine: String {
        if let lastError = model.lastError {
            return lastError
        }
        if model.endpoint == nil {
            return "Нет адреса API"
        }
        if let host = model.endpoint?.host() {
            if let lastUpdated = model.lastUpdated {
                return "\(host) · \(lastUpdated.formatted(date: .omitted, time: .shortened))"
            }
            return host
        }
        return "Подключено"
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

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Button {
                model.toggle(task)
            } label: {
                Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.done ? Color.accentColor : .secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help(task.done ? "Вернуть в работу" : "Отметить выполненной")

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.body)
                    .strikethrough(task.done)
                    .foregroundStyle(task.done ? .secondary : .primary)
                    .lineLimit(2)
                if let due = DueLabel.make(task.due) {
                    Text(due.text)
                        .font(.caption)
                        .foregroundStyle(due.overdue && !task.done ? Color.orange : .secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                model.open(task)
            }

            if task.url != nil || !model.appURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
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

struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        DragView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

final class DragView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
}
