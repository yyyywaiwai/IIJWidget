import Foundation

/// Handles HTTP construction, response validation and token-excluding debug recording.
/// Endpoint orchestration and persisted authentication live in MyIIJmioAPIClient.
final class GAPIHTTPClient {
    private let baseURL = URL(string: "https://gapi.iijmio.jp")!
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private let debugStore = DebugResponseStore.shared
    private let debugResponsesEnabled: Bool

    init(debugResponsesEnabled: Bool, session: URLSession? = nil) {
        self.debugResponsesEnabled = debugResponsesEnabled
        self.session = session ?? Self.makeSession()
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 45
        configuration.timeoutIntervalForResource = 60
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration)
    }

    func get<Response: Decodable>(
        path: String,
        authorization: String,
        query: [URLQueryItem] = [],
        forceUpdate: Bool = false
    ) async throws -> Response {
        try await request(
            path: path,
            method: "GET",
            authorization: authorization,
            query: query,
            forceUpdate: forceUpdate,
            body: Optional<EmptyRequestBody>.none
        )
    }

    func request<Response: Decodable, Body: Encodable>(
        path: String,
        method: String,
        authorization: String,
        query: [URLQueryItem] = [],
        forceUpdate: Bool = false,
        body: Body?
    ) async throws -> Response {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw MyIIJmioAPIError.invalidURL(path)
        }
        let filteredQuery = query.filter { item in
            guard let value = item.value else { return false }
            return !value.isEmpty
        }
        components.queryItems = filteredQuery.isEmpty ? nil : filteredQuery
        guard let url = components.url else {
            throw MyIIJmioAPIError.invalidURL(path)
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method
        urlRequest.timeoutInterval = 45
        urlRequest.cachePolicy = .reloadIgnoringLocalCacheData
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("utf-8", forHTTPHeaderField: "charset")
        urlRequest.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        urlRequest.setValue(authorization, forHTTPHeaderField: "Authorization")
        urlRequest.setValue("45000", forHTTPHeaderField: "timeout")
        if forceUpdate {
            urlRequest.setValue("1", forHTTPHeaderField: "ForceUpdate")
        }
        if let body {
            urlRequest.httpBody = try encoder.encode(body)
        }

        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MyIIJmioAPIError.invalidResponse
        }

        recordResponse(path: path, statusCode: httpResponse.statusCode, data: data)

        switch httpResponse.statusCode {
        case 200..<300:
            break
        case 401, 403:
            throw MyIIJmioAPIError.invalidSession
        case 505:
            throw MyIIJmioAPIError.forcedUpdate
        default:
            throw MyIIJmioAPIError.httpError(httpResponse.statusCode)
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            if debugResponsesEnabled, path != "/token" {
                debugStore.appendResponse(
                    title: "GAPI decode failure",
                    path: path,
                    category: .api,
                    rawText: DebugPrettyFormatter.utf8String(from: data),
                    formattedText: nil
                )
            }
            throw error
        }
    }

    private func recordResponse(path: String, statusCode: Int, data: Data) {
        guard debugResponsesEnabled, path != "/token" else { return }
        let rawText = DebugPrettyFormatter.utf8String(from: data)
        debugStore.appendResponse(
            title: "GAPI \(statusCode)",
            path: path,
            category: .api,
            rawText: rawText,
            formattedText: DebugPrettyFormatter.prettyJSON(from: data)
        )
    }
}

private struct EmptyRequestBody: Encodable {}
