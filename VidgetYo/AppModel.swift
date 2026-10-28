import AppKit
import Observation

@MainActor
@Observable
final class AppModel {
    private enum Keys {
        static let url = "vidgetyo.tasksURL"
        static let token = "vidgetyo.token"
        static let appURL = "vidgetyo.appURL"
        static let refresh = "vidgetyo.refreshSeconds"
        static let float = "vidgetyo.floatAboveWindows"
        static let showCompleted = "vidgetyo.showCompleted"
        static let visible = "vidgetyo.widgetVisible"
        static let cache = "vidgetyo.cachedTasks"
        static let origin = "vidgetyo.origin"
    }

    private let defaults = UserDefaults.standard
    private let client = TaskClient()
    private var pollTask: Task<Void, Never>?

    var tasks: [TaskItem] = []
    var lastError: String?
    var lastUpdated: Date?
    var isRefreshing = false
    var presentSettings: () -> Void = {}

    var tasksURL: String {
        didSet { persistSettings() }
    }
    var token: String {
        didSet { persistSettings() }
    }
    var appURL: String {
        didSet { persistSettings() }
    }
    var refreshSeconds: Int {
        didSet {
            let clamped = min(600, max(15, refreshSeconds))
            if clamped != refreshSeconds {
                refreshSeconds = clamped
                return
            }
            guard refreshSeconds != oldValue else { return }
            persistSettings()
            startPolling()
        }
    }
    var floatAboveWindows: Bool {
        didSet {
            guard floatAboveWindows != oldValue else { return }
            persistSettings()
            controller?.applyLevel()
        }
    }
    var showCompleted: Bool {
        didSet { persistSettings() }
    }
    var widgetVisible: Bool {
        didSet {
            guard widgetVisible != oldValue else { return }
            persistSettings()
            if widgetVisible {
                controller?.show()
            } else {
                controller?.hide()
            }
        }
    }

    weak var controller: DesktopWidgetController?

    var endpoint: URL? {
        let trimmed = tasksURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else { return nil }
        guard scheme == "https" || scheme == "http" else { return nil }
        return url
    }

    var visibleTasks: [TaskItem] {
        tasks.filter { showCompleted || !$0.done }
    }

    var openCount: Int {
        tasks.filter { !$0.done }.count
    }

    init() {
        let storedRefresh = defaults.object(forKey: Keys.refresh) as? Int ?? 60
        tasksURL = defaults.string(forKey: Keys.url) ?? ""
        token = defaults.string(forKey: Keys.token) ?? ""
        appURL = defaults.string(forKey: Keys.appURL) ?? ""
        refreshSeconds = min(600, max(15, storedRefresh))
        floatAboveWindows = defaults.object(forKey: Keys.float) as? Bool ?? false
        showCompleted = defaults.object(forKey: Keys.showCompleted) as? Bool ?? true
        widgetVisible = defaults.object(forKey: Keys.visible) as? Bool ?? true
        if let data = defaults.data(forKey: Keys.cache),
           let cached = try? JSONDecoder().decode([TaskItem].self, from: data) {
            tasks = cached
        }
    }

    func start() {
        startPolling()
        Task { await refresh() }
    }

    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                let seconds = self?.refreshSeconds ?? 60
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled else { return }
                await self?.refresh()
            }
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        guard let endpoint else {
            lastError = nil
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            tasks = try await client.fetch(collection: endpoint, token: token)
            lastError = nil
            lastUpdated = Date()
            cacheTasks()
        } catch {
            lastError = TaskErrorText.describe(error)
        }
    }

    func toggle(_ task: TaskItem) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index].done.toggle()
        cacheTasks()
        let updated = tasks[index]
        guard let endpoint else { return }
        Task {
            do {
                try await client.setDone(collection: endpoint, id: updated.id, done: updated.done, token: token)
                lastError = nil
            } catch {
                if let current = tasks.firstIndex(where: { $0.id == updated.id }) {
                    tasks[current].done = !updated.done
                    cacheTasks()
                }
                lastError = TaskErrorText.describe(error)
            }
        }
    }

    func add(title: String) async {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let endpoint else { return }
        let temporary = TaskItem(id: "local-\(UUID().uuidString)", title: title, done: false)
        tasks.insert(temporary, at: 0)
        do {
            try await client.create(collection: endpoint, title: title, token: token)
            tasks.removeAll { $0.id == temporary.id }
            isRefreshing = false
            await refresh()
        } catch {
            tasks.removeAll { $0.id == temporary.id }
            lastError = TaskErrorText.describe(error)
        }
    }

    func open(_ task: TaskItem) {
        if let link = httpURL(task.url) {
            NSWorkspace.shared.open(link)
            return
        }
        if let link = httpURL(appURL) {
            NSWorkspace.shared.open(link)
        }
    }

    func openApp() {
        guard let link = httpURL(appURL) else { return }
        NSWorkspace.shared.open(link)
    }

    func savedOrigin() -> NSPoint? {
        guard let raw = defaults.string(forKey: Keys.origin) else { return nil }
        let parts = raw.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 2 else { return nil }
        return NSPoint(x: parts[0], y: parts[1])
    }

    func saveOrigin(_ origin: NSPoint) {
        defaults.set("\(origin.x),\(origin.y)", forKey: Keys.origin)
    }

    private func httpURL(_ raw: String?) -> URL? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else { return nil }
        guard scheme == "https" || scheme == "http" else { return nil }
        return url
    }

    private func cacheTasks() {
        if let data = try? JSONEncoder().encode(tasks) {
            defaults.set(data, forKey: Keys.cache)
        }
    }

    private func persistSettings() {
        defaults.set(tasksURL, forKey: Keys.url)
        defaults.set(token, forKey: Keys.token)
        defaults.set(appURL, forKey: Keys.appURL)
        defaults.set(refreshSeconds, forKey: Keys.refresh)
        defaults.set(floatAboveWindows, forKey: Keys.float)
        defaults.set(showCompleted, forKey: Keys.showCompleted)
        defaults.set(widgetVisible, forKey: Keys.visible)
    }
}
