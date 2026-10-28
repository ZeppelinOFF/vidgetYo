import Foundation

struct CapturedRequest: Sendable {
    var url: URL
    var method: String
    var body: Data
    var authorization: String?
}

final class RequestLog: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [CapturedRequest] = []

    func add(_ request: URLRequest) {
        let captured = CapturedRequest(
            url: request.url ?? YozhkaClient.site,
            method: request.httpMethod ?? "",
            body: Self.body(of: request),
            authorization: request.value(forHTTPHeaderField: "Authorization")
        )
        lock.lock()
        stored.append(captured)
        lock.unlock()
    }

    var requests: [CapturedRequest] {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    private static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1024)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: 1024)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

final class YozhkaStubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responder: ((URLRequest) -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let responder = Self.responder else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (status, body) = responder(request)
        let response = HTTPURLResponse(
            url: request.url ?? YozhkaClient.site,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

func makeYozhkaClient(accessToken: String = "", refreshToken: String = "") -> YozhkaClient {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [YozhkaStubURLProtocol.self]
    configuration.timeoutIntervalForRequest = 5
    return YozhkaClient(
        accessToken: accessToken,
        refreshToken: refreshToken,
        session: URLSession(configuration: configuration)
    )
}

func queryItems(_ url: URL) -> [String: String] {
    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
}
