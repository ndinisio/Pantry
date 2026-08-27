import Foundation

/// A small `URLSession` wrapper with the behaviour every network call in the app needs:
/// timeouts, status handling, retry with exponential backoff for transient failures,
/// and cooperative cancellation.
struct HTTPClient {

    var session: URLSession
    /// Attempts, including the first. 3 means one call plus two retries.
    var maxAttempts: Int = 3
    /// Base delay for backoff; doubled each attempt with a little jitter.
    var baseRetryDelay: TimeInterval = 0.8

    init(timeout: TimeInterval = 30) {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout * 2
        configuration.waitsForConnectivity = false
        self.session = URLSession(configuration: configuration)
    }

    init(session: URLSession) {
        self.session = session
    }

    /// Sends `request`, retrying transient failures. Throws `AIError` so callers have a
    /// single error vocabulary regardless of where a failure came from.
    func send(_ request: URLRequest) async throws -> Data {
        var lastError: AIError = .server(status: 0, message: nil)

        for attempt in 1...max(1, maxAttempts) {
            try Task.checkCancellation()
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw AIError.invalidResponse(detail: "Response was not HTTP")
                }

                switch http.statusCode {
                case 200..<300:
                    return data

                case 429:
                    let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
                    lastError = .rateLimited(retryAfter: retryAfter)

                case 401, 403:
                    // Never retried: a rejected credential will be rejected again.
                    throw AIError.server(status: http.statusCode, message: "Authentication failed")

                case 400..<500:
                    throw AIError.server(status: http.statusCode, message: message(in: data))

                default:
                    lastError = .server(status: http.statusCode, message: message(in: data))
                }
            } catch let error as AIError {
                guard error.isTransient else { throw error }
                lastError = error
            } catch is CancellationError {
                throw AIError.cancelled
            } catch let error as URLError {
                switch error.code {
                case .cancelled: throw AIError.cancelled
                case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                    throw AIError.offline
                case .timedOut:
                    lastError = .timedOut
                default:
                    lastError = .server(status: error.errorCode, message: error.localizedDescription)
                }
            }

            if attempt < maxAttempts {
                try await backOff(afterAttempt: attempt, error: lastError)
            }
        }
        throw lastError
    }

    private func backOff(afterAttempt attempt: Int, error: AIError) async throws {
        var delay = baseRetryDelay * pow(2, Double(attempt - 1))
        if case .rateLimited(let retryAfter) = error, let retryAfter {
            delay = max(delay, retryAfter)
        }
        // A little jitter so simultaneous requests don't retry in lockstep.
        delay += Double.random(in: 0...0.3)
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }

    /// Best-effort extraction of a provider's error message for the log.
    private func message(in data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8)
        }
        if let error = object["error"] as? [String: Any], let message = error["message"] as? String {
            return message
        }
        return object["message"] as? String
    }
}
