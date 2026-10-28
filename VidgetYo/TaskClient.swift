import Foundation

struct TaskItem: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var done: Bool
    var due: String?
    var url: String?
    var status: String?

    init(id: String, title: String, done: Bool, due: String? = nil, url: String? = nil, status: String? = nil) {
        self.id = id
        self.title = title
        self.done = done
        self.due = due
        self.url = url
        self.status = status
    }
}

struct YozhkaPlace: Identifiable, Hashable, Sendable {
    var id: Int
    var title: String
    var code: String
}

struct YozhkaSession: Sendable {
    var accessToken: String
    var refreshToken: String
    var mail: String
    var fullName: String
}

enum YozhkaError: Error {
    case unauthorized
    case badStatus(Int, String)
    case invalidResponse
}

actor YozhkaClient {
    nonisolated static let site = URL(string: "https://yozhka.lukit.ru")!

    private let session: URLSession
    private let decoder = JSONDecoder()
    private var accessToken: String
    private var refreshToken: String

    init(accessToken: String, refreshToken: String, session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 20
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.httpAdditionalHeaders = ["User-Agent": "VidgetYo/1.0"]
            self.session = URLSession(configuration: configuration)
        }
        self.accessToken = accessToken
        self.refreshToken = refreshToken
    }

    func replaceSession(accessToken: String, refreshToken: String) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
    }

    func tokens() -> (access: String, refresh: String) {
        (accessToken, refreshToken)
    }

    func login(mail: String, password: String) async throws -> YozhkaSession {
        let body = try JSONEncoder().encode([
            "mail": mail,
            "password": password,
            "deviceType": "web"
        ])
        let data = try await send(
            request(path: "/auth/login", method: "POST", body: body, authorized: false),
            refreshOnUnauthorized: false
        )
        let session = try decode(AuthPayload.self, from: data).session
        accessToken = session.accessToken
        refreshToken = session.refreshToken
        return session
    }

    func logout() async {
        let token = refreshToken
        guard !token.isEmpty else { return }
        let body = try? JSONEncoder().encode(["refreshToken": token, "deviceType": "web"])
        _ = try? await send(
            request(path: "/auth/logout", method: "POST", body: body, authorized: true),
            refreshOnUnauthorized: false
        )
    }

    func workspaces() async throws -> [YozhkaPlace] {
        try await pages(path: "/workspace/my", extra: [])
    }

    func projects(workspaceID: Int) async throws -> [YozhkaPlace] {
        try await pages(path: "/project/tiles/my", extra: [
            URLQueryItem(name: "workspaceId", value: String(workspaceID))
        ])
    }

    func tasks(projectID: Int, projectCode: String) async throws -> [TaskItem] {
        var collected: [TaskItem] = []
        var pageIndex = 1
        var totalPages = 1
        while pageIndex <= totalPages && pageIndex <= 5 {
            let data = try await send(request(
                path: "/task/\(projectID)/list",
                method: "GET",
                query: [
                    URLQueryItem(name: "page", value: String(pageIndex)),
                    URLQueryItem(name: "size", value: "100")
                ],
                body: nil,
                authorized: true
            ))
            let page = try decode(TaskPage.self, from: data)
            totalPages = max(page.totalPages ?? 1, 1)
            collected.append(contentsOf: page.content.map { $0.task(projectCode: projectCode) })
            pageIndex += 1
        }
        return collected
    }

    func createTask(projectID: Int, title: String) async throws {
        let body = try JSONEncoder().encode(CreateTaskBody(title: title, projectId: projectID))
        _ = try await send(request(
            path: "/task",
            method: "POST",
            query: [URLQueryItem(name: "projectId", value: String(projectID))],
            body: body,
            authorized: true
        ))
    }

    func toggleCompletion(taskID: String) async throws {
        _ = try await send(request(
            path: "/task/\(taskID)/toggleCompletion",
            method: "POST",
            body: nil,
            authorized: true
        ))
    }

    private func pages(path: String, extra: [URLQueryItem]) async throws -> [YozhkaPlace] {
        var collected: [YozhkaPlace] = []
        var pageIndex = 1
        var totalPages = 1
        while pageIndex <= totalPages && pageIndex <= 5 {
            var query = extra
            query.append(URLQueryItem(name: "page", value: String(pageIndex)))
            query.append(URLQueryItem(name: "size", value: "24"))
            let data = try await send(request(path: path, method: "GET", query: query, body: nil, authorized: true))
            let page = try Self.parsedPage(from: data)
            totalPages = page.totalPages
            collected.append(contentsOf: page.places)
            pageIndex += 1
        }
        return collected
    }

    private static func parsedPage(from data: Data) throws -> (places: [YozhkaPlace], totalPages: Int) {
        let json = try JSONSerialization.jsonObject(with: data)
        let list = rows(in: json)
        let places = list.compactMap(place(from:))
        if places.isEmpty, let first = list.first {
            let keys = first.keys.sorted().joined(separator: ", ")
            throw YozhkaError.badStatus(200, "В списке нет id. Поля: \(keys)")
        }
        let totalPages = max(integer(object(json)?["totalPages"]) ?? 1, 1)
        return (places, totalPages)
    }

    private static func rows(in json: Any) -> [[String: Any]] {
        if let rows = list(json)?.compactMap(object), !rows.isEmpty {
            return rows
        }
        guard let container = object(json) else { return [] }
        for key in ["content", "data", "items"] {
            if let rows = list(container[key])?.compactMap(object), !rows.isEmpty {
                return rows
            }
            if let nested = container[key] {
                let inner = rows(in: nested)
                if !inner.isEmpty {
                    return inner
                }
            }
        }
        return []
    }

    private static func object(_ value: Any?) -> [String: Any]? {
        guard let value else { return nil }
        if let dict = value as? [String: Any] {
            return dict
        }
        guard let dict = value as? NSDictionary else { return nil }
        var result: [String: Any] = [:]
        result.reserveCapacity(dict.count)
        for (key, item) in dict {
            guard let key = key as? String else { continue }
            result[key] = item
        }
        return result
    }

    private static func list(_ value: Any?) -> [Any]? {
        guard let value else { return nil }
        if let array = value as? [Any] {
            return array
        }
        if let array = value as? NSArray {
            return array.map { $0 }
        }
        return nil
    }

    private static func place(from row: [String: Any]) -> YozhkaPlace? {
        guard let id = integer(row["id"]) ?? integer(row["workspaceId"]) ?? integer(row["projectId"]) else {
            return nil
        }
        let title = text(row["title"]) ?? text(row["name"]) ?? text(row["code"]) ?? "Без названия"
        let code = text(row["code"]) ?? ""
        return YozhkaPlace(id: id, title: title, code: code)
    }

    private static func integer(_ value: Any?) -> Int? {
        switch value {
        case let text as String:
            return Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
        case let number as NSNumber:
            if number === (kCFBooleanTrue as NSNumber) || number === (kCFBooleanFalse as NSNumber) {
                return nil
            }
            return number.intValue
        default:
            return nil
        }
    }

    private static func text(_ value: Any?) -> String? {
        guard let value else { return nil }
        if value is NSNull { return nil }
        let raw = (value as? String) ?? String(describing: value)
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func request(
        path: String,
        method: String,
        query: [URLQueryItem] = [],
        body: Data?,
        authorized: Bool
    ) -> URLRequest {
        let suffix = path.hasPrefix("/") ? path : "/" + path
        var components = URLComponents()
        components.scheme = "https"
        components.host = "yozhka.lukit.ru"
        components.path = "/backend" + suffix
        if !query.isEmpty {
            components.queryItems = query
        }
        var request = URLRequest(url: components.url ?? Self.site)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if authorized, !accessToken.isEmpty {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func send(_ request: URLRequest, refreshOnUnauthorized: Bool = true) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw YozhkaError.invalidResponse
        }
        if http.statusCode == 401 {
            guard refreshOnUnauthorized, !refreshToken.isEmpty, request.url?.path.hasSuffix("/auth/refresh") != true else {
                throw YozhkaError.unauthorized
            }
            try await refresh()
            var retry = request
            retry.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            return try await send(retry, refreshOnUnauthorized: false)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw YozhkaError.badStatus(http.statusCode, Self.message(from: data))
        }
        return data
    }

    private func refresh() async throws {
        let body = try JSONEncoder().encode(["refreshToken": refreshToken])
        let data = try await send(
            request(path: "/auth/refresh", method: "POST", body: body, authorized: false),
            refreshOnUnauthorized: false
        )
        let session = try decode(AuthPayload.self, from: data).session
        accessToken = session.accessToken
        refreshToken = session.refreshToken
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw YozhkaError.invalidResponse
        }
    }

    private static func message(from data: Data) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["message", "error"] {
                if let text = object[key] as? String {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        return String(trimmed.prefix(160))
                    }
                }
            }
        }
        let snippet = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return String(snippet.prefix(160))
    }
}

private struct AuthPayload: Decodable {
    var accessToken: String
    var refreshToken: String
    var mail: String?
    var fullName: String?

    var session: YozhkaSession {
        YozhkaSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            mail: mail ?? "",
            fullName: fullName ?? ""
        )
    }
}

private struct TaskPage: Decodable {
    var content: [TaskPayload]
    var totalPages: Int?
}

private struct TaskPayload: Decodable {
    var id: Int
    var title: String?
    var code: String?
    var isCompleted: Bool?
    var deadlineTs: String?
    var statusName: String?

    func task(projectCode: String) -> TaskItem {
        let name = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = (name?.isEmpty == false ? name : nil) ?? code ?? "Задача"
        var link: String?
        if !projectCode.isEmpty {
            link = "https://yozhka.lukit.ru/project/\(projectCode)"
        }
        return TaskItem(
            id: String(id),
            title: resolved,
            done: isCompleted ?? false,
            due: deadlineTs,
            url: link,
            status: statusName
        )
    }
}

private struct CreateTaskBody: Encodable {
    var title: String
    var projectId: Int
}

enum TaskErrorText {
    static func describe(_ error: Error) -> String {
        if let client = error as? YozhkaError {
            switch client {
            case .unauthorized:
                return "Нужно войти снова"
            case .invalidResponse:
                return "Непонятный ответ Ёжки"
            case let .badStatus(code, body):
                if code == 401 || code == 403 {
                    return body.isEmpty ? "Неверный логин или пароль" : body
                }
                return body.isEmpty ? "Ёжка ответила \(code)" : body
            }
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet:
                return "Нет интернета"
            case .cannotFindHost, .cannotConnectToHost, .networkConnectionLost:
                return "Ёжка недоступна"
            case .timedOut:
                return "Ёжка не ответила вовремя"
            default:
                return "Ошибка сети"
            }
        }
        return error.localizedDescription
    }
}
