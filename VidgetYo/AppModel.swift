import AppKit
import Observation

enum OriginStore {
    static let key = "vidgetyo.origin"

    static func save(_ origin: NSPoint) {
        UserDefaults.standard.set("\(origin.x),\(origin.y)", forKey: key)
    }

    static func load() -> NSPoint? {
        guard let raw = UserDefaults.standard.string(forKey: key) else { return nil }
        let parts = raw.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 2 else { return nil }
        return NSPoint(x: parts[0], y: parts[1])
    }
}

@MainActor
@Observable
final class AppModel {
    private enum Keys {
        static let access = "vidgetyo.accessToken"
        static let refresh = "vidgetyo.refreshToken"
        static let mail = "vidgetyo.mail"
        static let fullName = "vidgetyo.fullName"
        static let workspaceID = "vidgetyo.workspaceID"
        static let workspaceTitle = "vidgetyo.workspaceTitle"
        static let projectID = "vidgetyo.projectID"
        static let projectTitle = "vidgetyo.projectTitle"
        static let projectCode = "vidgetyo.projectCode"
        static let refreshSeconds = "vidgetyo.refreshSeconds"
        static let float = "vidgetyo.floatAboveWindows"
        static let showCompleted = "vidgetyo.showCompleted"
        static let visible = "vidgetyo.widgetVisible"
        static let cache = "vidgetyo.cachedTasks"
    }

    private let defaults = UserDefaults.standard
    private let client: YozhkaClient
    private var pollTask: Task<Void, Never>?

    var tasks: [TaskItem] = []
    var workspaces: [YozhkaPlace] = []
    var projects: [YozhkaPlace] = []
    var lastError: String?
    var lastUpdated: Date?
    var isRefreshing = false
    var isSigningIn = false
    var isLoadingCatalog = false
    var presentSettings: () -> Void = {}

    var mail: String
    var fullName: String
    private var accessToken: String
    private var refreshToken: String

    var workspaceID: Int?
    var workspaceTitle: String
    var projectID: Int?
    var projectTitle: String
    var projectCode: String

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

    var isLoggedIn: Bool {
        !refreshToken.isEmpty
    }

    var isConnected: Bool {
        isLoggedIn && projectID != nil
    }

    var visibleTasks: [TaskItem] {
        tasks.filter { showCompleted || !$0.done }
    }

    var openCount: Int {
        tasks.filter { !$0.done }.count
    }

    var heading: String {
        projectTitle.isEmpty ? "Ёжка" : projectTitle
    }

    init() {
        let storedRefresh = defaults.object(forKey: Keys.refreshSeconds) as? Int ?? 60
        let storedAccess = defaults.string(forKey: Keys.access) ?? ""
        let storedSession = defaults.string(forKey: Keys.refresh) ?? ""
        accessToken = storedAccess
        refreshToken = storedSession
        client = YozhkaClient(accessToken: storedAccess, refreshToken: storedSession)
        mail = defaults.string(forKey: Keys.mail) ?? ""
        fullName = defaults.string(forKey: Keys.fullName) ?? ""
        workspaceTitle = defaults.string(forKey: Keys.workspaceTitle) ?? ""
        projectTitle = defaults.string(forKey: Keys.projectTitle) ?? ""
        projectCode = defaults.string(forKey: Keys.projectCode) ?? ""
        workspaceID = defaults.object(forKey: Keys.workspaceID) as? Int
        projectID = defaults.object(forKey: Keys.projectID) as? Int
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
        Task { await restore() }
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

    func signIn(mail: String, password: String) async {
        let mail = mail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !mail.isEmpty, !password.isEmpty, !isSigningIn else { return }
        isSigningIn = true
        defer { isSigningIn = false }
        do {
            let session = try await client.login(mail: mail, password: password)
            apply(session)
            lastError = nil
            await loadWorkspaces()
            if workspaces.count == 1, let only = workspaces.first {
                await selectWorkspace(only.id)
            }
        } catch {
            if let yozhka = error as? YozhkaError, case .unauthorized = yozhka {
                lastError = "Неверный логин или пароль"
            } else {
                lastError = TaskErrorText.describe(error)
            }
        }
    }

    func signOut() {
        let client = client
        Task {
            await client.logout()
            await client.replaceSession(accessToken: "", refreshToken: "")
        }
        accessToken = ""
        refreshToken = ""
        mail = ""
        fullName = ""
        workspaceID = nil
        workspaceTitle = ""
        projectID = nil
        projectTitle = ""
        projectCode = ""
        workspaces = []
        projects = []
        tasks = []
        lastError = nil
        lastUpdated = nil
        defaults.removeObject(forKey: Keys.cache)
        persistSettings()
    }

    func selectWorkspace(_ id: Int) async {
        guard let place = workspaces.first(where: { $0.id == id }) ?? (workspaceID == id ? currentWorkspace : nil) else { return }
        workspaceID = place.id
        workspaceTitle = place.title
        projectID = nil
        projectTitle = ""
        projectCode = ""
        tasks = []
        persistSettings()
        await loadProjects()
        if projects.count == 1, let only = projects.first {
            await selectProject(only.id)
        }
    }

    func selectProject(_ id: Int) async {
        guard let place = projects.first(where: { $0.id == id }) else { return }
        projectID = place.id
        projectTitle = place.title
        projectCode = place.code
        persistSettings()
        await refresh()
    }

    func refresh() async {
        guard !isRefreshing, let projectID else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            tasks = try await client.tasks(projectID: projectID, projectCode: projectCode)
            await rememberTokens()
            lastError = nil
            lastUpdated = Date()
            cacheTasks()
        } catch {
            await rememberTokens()
            await handle(error)
        }
    }

    func toggle(_ task: TaskItem) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index].done.toggle()
        cacheTasks()
        let updated = tasks[index]
        Task {
            do {
                try await client.toggleCompletion(taskID: updated.id)
                await rememberTokens()
                lastError = nil
                await refresh()
            } catch {
                if let current = tasks.firstIndex(where: { $0.id == updated.id }) {
                    tasks[current].done = !updated.done
                    cacheTasks()
                }
                await rememberTokens()
                await handle(error)
            }
        }
    }

    func add(title: String) async {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let projectID else { return }
        let temporary = TaskItem(id: "local-\(UUID().uuidString)", title: title, done: false)
        tasks.insert(temporary, at: 0)
        do {
            try await client.createTask(projectID: projectID, title: title)
            await rememberTokens()
            tasks.removeAll { $0.id == temporary.id }
            isRefreshing = false
            await refresh()
        } catch {
            tasks.removeAll { $0.id == temporary.id }
            await rememberTokens()
            await handle(error)
        }
    }

    func open(_ task: TaskItem) {
        guard let link = httpURL(task.url) else { return }
        NSWorkspace.shared.open(link)
    }

    func openSite() {
        NSWorkspace.shared.open(YozhkaClient.site)
    }

    func savedOrigin() -> NSPoint? {
        OriginStore.load()
    }

    nonisolated func saveOrigin(_ origin: NSPoint) {
        OriginStore.save(origin)
    }

    private var currentWorkspace: YozhkaPlace? {
        guard let workspaceID else { return nil }
        return YozhkaPlace(id: workspaceID, title: workspaceTitle, code: "")
    }

    private func restore() async {
        guard isLoggedIn else { return }
        await loadWorkspaces()
        if let workspaceID {
            if workspaces.contains(where: { $0.id == workspaceID }) == false, !workspaceTitle.isEmpty {
                workspaces.insert(YozhkaPlace(id: workspaceID, title: workspaceTitle, code: ""), at: 0)
            }
            await loadProjects()
        }
        if projectID != nil {
            await refresh()
        }
    }

    private func loadWorkspaces() async {
        isLoadingCatalog = true
        defer { isLoadingCatalog = false }
        do {
            workspaces = try await client.workspaces()
            await rememberTokens()
            lastError = nil
        } catch {
            await rememberTokens()
            await handle(error)
        }
    }

    private func loadProjects() async {
        guard let workspaceID else {
            projects = []
            return
        }
        isLoadingCatalog = true
        defer { isLoadingCatalog = false }
        do {
            projects = try await client.projects(workspaceID: workspaceID)
            await rememberTokens()
            if let projectID, projects.contains(where: { $0.id == projectID }) == false, !projectTitle.isEmpty {
                projects.insert(YozhkaPlace(id: projectID, title: projectTitle, code: projectCode), at: 0)
            }
            lastError = nil
        } catch {
            await rememberTokens()
            await handle(error)
        }
    }

    private func apply(_ session: YozhkaSession) {
        accessToken = session.accessToken
        refreshToken = session.refreshToken
        mail = session.mail
        fullName = session.fullName
        persistSettings()
    }

    private func rememberTokens() async {
        let pair = await client.tokens()
        guard pair.access != accessToken || pair.refresh != refreshToken else { return }
        accessToken = pair.access
        refreshToken = pair.refresh
        persistSettings()
    }

    private func handle(_ error: Error) async {
        if let clientError = error as? YozhkaError, case .unauthorized = clientError {
            signOut()
            presentSettings()
        }
        lastError = TaskErrorText.describe(error)
    }

    private func httpURL(_ raw: String?) -> URL? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme?.lowercased() == "https" else { return nil }
        return url
    }

    private func cacheTasks() {
        if let data = try? JSONEncoder().encode(tasks) {
            defaults.set(data, forKey: Keys.cache)
        }
    }

    private func persistSettings() {
        defaults.set(accessToken, forKey: Keys.access)
        defaults.set(refreshToken, forKey: Keys.refresh)
        defaults.set(mail, forKey: Keys.mail)
        defaults.set(fullName, forKey: Keys.fullName)
        defaults.set(workspaceTitle, forKey: Keys.workspaceTitle)
        defaults.set(projectTitle, forKey: Keys.projectTitle)
        defaults.set(projectCode, forKey: Keys.projectCode)
        if let workspaceID {
            defaults.set(workspaceID, forKey: Keys.workspaceID)
        } else {
            defaults.removeObject(forKey: Keys.workspaceID)
        }
        if let projectID {
            defaults.set(projectID, forKey: Keys.projectID)
        } else {
            defaults.removeObject(forKey: Keys.projectID)
        }
        defaults.set(refreshSeconds, forKey: Keys.refreshSeconds)
        defaults.set(floatAboveWindows, forKey: Keys.float)
        defaults.set(showCompleted, forKey: Keys.showCompleted)
        defaults.set(widgetVisible, forKey: Keys.visible)
    }
}
