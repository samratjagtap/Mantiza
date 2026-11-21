import Foundation

struct AIError: LocalizedError, Equatable {
    let message: String
    var status: Int?
    var errorDescription: String? { message }
    init(_ message: String, status: Int? = nil) { self.message = message; self.status = status }

    /// Answers a retry with a fresh request can fix (not refusals, keys or rate limits).
    static let cutOff = AIError("The model's answer was cut off.")
    static let notJSON = AIError("The model did not answer with JSON.")
}

/// One shared session for every AI call, so TLS connections stay warm between steps.
enum HTTP {
    nonisolated(unsafe) static var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: config)
    }()

    /// Status codes worth retrying: rate limited, overloaded, server errors.
    static func retryable(_ status: Int) -> Bool { status == 429 || status == 529 || (500...599).contains(status) }

    /// Network failures worth one more try. A model request has no side effects, so repeating it is safe.
    static func retryable(_ error: Error) -> Bool {
        [URLError.timedOut, .networkConnectionLost, .notConnectedToInternet].contains((error as? URLError)?.code)
    }

    /// The server could not be reached at all (wrong address, other network, nothing listening).
    static func unreachable(_ error: Error) -> Bool {
        retryable(error) || [URLError.cannotConnectToHost, .cannotFindHost, .dnsLookupFailed]
            .contains((error as? URLError)?.code)
    }

    /// POST JSON and return the decoded JSON object. Retries 429/529/5xx with backoff (honouring retry-after),
    /// and a timed-out or dropped request once unless `networkRetry` is off.
    static func postJSON(_ url: URL, headers: [String: String], body: [String: Any], timeout: Double,
                         retries: Int = 2, networkRetry: Bool = true, service: String) async throws -> [String: Any] {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        var attempt = 0, networkRetried = !networkRetry
        while true {
            let data: Data, response: URLResponse
            do { (data, response) = try await session.data(for: request) } catch where retryable(error) && !networkRetried {
                networkRetried = true
                Log.info("\(service) request failed (\(error.localizedDescription)), trying once more")
                try await Task.sleep(for: .milliseconds(500))
                continue
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { return json }
            let detail = String(decoding: data.prefix(400), as: UTF8.self)
            if retryable(status) && attempt < retries {
                attempt += 1
                let after = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "retry-after").flatMap(Double.init)
                let wait = min(after ?? pow(2, Double(attempt)) * 0.5, 10)
                Log.info("\(service) HTTP \(status), retry \(attempt) in \(wait) s")
                try await Task.sleep(for: .seconds(wait))
                continue
            }
            switch status {
            case 401, 403: throw AIError("\(service) rejected the API key. Check it in Settings.", status: status)
            case 429: throw AIError("\(service) is rate limiting this key. Try again in a minute.", status: status)
            default: throw AIError("\(service) error \(status): \(detail)", status: status)
            }
        }
    }

    /// The first JSON object inside a model's text (tolerates code fences and stray words around it).
    static func jsonObject(in text: String) -> [String: Any]? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else { return nil }
        return try? JSONSerialization.jsonObject(with: Data(text[start...end].utf8)) as? [String: Any]
    }
}
