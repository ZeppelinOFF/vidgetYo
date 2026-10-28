import Foundation

struct TaskItem: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var done: Bool
    var due: String?
    var url: String?

    init(id: String, title: String, done: Bool, due: String? = nil, url: String? = nil) {
        self.id = id
        self.title = title
        self.done = done
        self.due = due
        self.url = url
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, name, done, completed, isDone, status, due, dueDate, url, link
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try? container.decode(String.self, forKey: .id) {
            id = value
        } else if let value = try? container.decode(Int.self, forKey: .id) {
            id = String(value)
        } else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "id")
        }

        if let value = try? container.decode(String.self, forKey: .title) {
            title = value
        } else {
            title = try container.decode(String.self, forKey: .name)
        }

        if let value = try? container.decode(Bool.self, forKey: .done) {
            done = value
        } else if let value = try? container.decode(Bool.self, forKey: .completed) {
            done = value
        } else if let value = try? container.decode(Bool.self, forKey: .isDone) {
            done = value
        } else if let value = try? container.decode(String.self, forKey: .status) {
            done = ["done", "completed", "closed"].contains(value.lowercased())
        } else {
            done = false
        }

        due = (try? container.decodeIfPresent(String.self, forKey: .due)) ?? (try? container.decodeIfPresent(String.self, forKey: .dueDate)) ?? nil
        url = (try? container.decodeIfPresent(String.self, forKey: .url)) ?? (try? container.decodeIfPresent(String.self, forKey: .link)) ?? nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(done, forKey: .done)
        try container.encodeIfPresent(due, forKey: .due)
        try container.encodeIfPresent(url, forKey: .url)
    }
}

enum TaskClientError: Error {
    case badStatus(Int, String)
    case invalidResponse
}

actor TaskClient {
    private let session: URLSession
    private let decoder = JSONDecoder()

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpAdditionalHeaders = ["User-Agent": "VidgetYo/1.0"]
        session = URLSession(configuration: configuration)
    }

    func fetch(collection: URL, token: String) async throws -> [TaskItem] {
        let data = try await send(request(url: collection, method: "GET", token: token, body: nil))
        return try decodeTasks(data)
    }

    func create(collection: URL, title: String, token: String) async throws {
        let body = try JSONEncoder().encode(["title": title])
        _ = try await send(request(url: collection, method: "POST", token: token, body: body))
    }

    func setDone(collection: URL, id: String, done: Bool, token: String) async throws {
        let body = try JSONEncoder().encode(["done": done])
        let url = Self.itemURL(collection: collection, id: id)
        _ = try await send(request(url: url, method: "PATCH", token: token, body: body))
    }

    private func decodeTasks(_ data: Data) throws -> [TaskItem] {
        if data.isEmpty {
            return []
        }
        if let items = try? decoder.decode([TaskItem].self, from: data) {
            return items
        }
        struct Envelope: Decodable {
            var tasks: [TaskItem]?
            var data: [TaskItem]?
            var items: [TaskItem]?
        }
        if let envelope = try? decoder.decode(Envelope.self, from: data) {
            if let tasks = envelope.tasks { return tasks }
            if let tasks = envelope.data { return tasks }
            if let tasks = envelope.items { return tasks }
        }
        throw TaskClientError.invalidResponse
    }

    private func request(url: URL, method: String, token: String, body: Data?) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            request.setValue("Bearer \(trimmed)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TaskClientError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let snippet = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw TaskClientError.badStatus(http.statusCode, String(snippet.prefix(120)))
        }
        return data
    }

    private static func itemURL(collection: URL, id: String) -> URL {
        guard var components = URLComponents(url: collection, resolvingAgainstBaseURL: false) else {
            return collection.appendingPathComponent(id)
        }
        var path = components.path
        if path.hasSuffix("/") {
            path.removeLast()
        }
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        components.path = path + "/" + encoded
        return components.url ?? collection.appendingPathComponent(id)
    }
}

enum TaskErrorText {
    static func describe(_ error: Error) -> String {
        if let client = error as? TaskClientError {
            switch client {
            case .invalidResponse:
                return "Непонятный ответ сервера"
            case let .badStatus(code, body):
                return body.isEmpty ? "Сервер ответил \(code)" : "Сервер ответил \(code): \(body)"
            }
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet:
                return "Нет интернета"
            case .cannotFindHost, .cannotConnectToHost, .networkConnectionLost:
                return "Сервер недоступен"
            case .timedOut:
                return "Сервер не ответил вовремя"
            case .appTransportSecurityRequiresSecureConnection:
                return "Нужен адрес https"
            default:
                return "Ошибка сети"
            }
        }
        return error.localizedDescription
    }
}
