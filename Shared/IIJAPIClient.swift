import Foundation

enum IIJAPIClientError: LocalizedError {
    case invalidCredentials
    case invalidURL(String)
    case invalidResponse
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "資格情報が設定されていません"
        case .invalidURL(let path):
            return "無効なURL: \(path)"
        case .invalidResponse:
            return "サーバーレスポンスを解釈できませんでした"
        case .httpError(let code):
            return "HTTPステータス \(code) で失敗しました"
        }
    }
}

struct APIErrorEnvelope: Decodable {
    let error: String?
}

final class IIJAPIClient {
    private let session: URLSession
    private let decoder = JSONDecoder()
    private var hasValidSession = false
    private var activeCredentials: Credentials?

    init() {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.httpCookieStorage = HTTPCookieStorage.sharedCookieStorage(forGroupContainerIdentifier: AppGroup.identifier)
        config.sharedContainerIdentifier = AppGroup.identifier
        config.httpAdditionalHeaders = [
            "Accept": "application/json",
            "User-Agent": "IIJFetcher/1.0"
        ]
        session = URLSession(configuration: config)
    }

    func fetchAll(credentials: Credentials) async throws -> AggregatePayload {
        guard !credentials.mioId.isEmpty, !credentials.password.isEmpty else {
            throw IIJAPIClientError.invalidCredentials
        }

        return try await performWithAutoLogin(credentials: credentials) {
            let top = try await fetchTop()
            let bill = try await fetchBillSummary()
            let status = try await fetchServiceStatus()
            return AggregatePayload(
                fetchedAt: Date(),
                top: top,
                bill: bill,
                serviceStatus: status
            )
        }
    }

    private func login(credentials: Credentials) async throws {
        let payload: [String: String] = [
            "mioId": credentials.mioId,
            "password": credentials.password
        ]
        let data = try await request(
            path: "/api/member/login",
            method: "POST",
            body: try JSONSerialization.data(withJSONObject: payload, options: [])
        )
        if let errorCode = try decodeAPIErrorIfNeeded(from: data) {
            throw NSError(domain: "IIJAPI", code: 0, userInfo: [NSLocalizedDescriptionKey: "ログインエラー: \(errorCode)"])
        }
    }

    private func fetchTop() async throws -> MemberTopResponse {
        let data = try await request(
            path: "/api/member/top",
            method: "POST",
            body: "{}".data(using: .utf8)
        )
        try throwIfAPIError(data)
        return try decoder.decode(MemberTopResponse.self, from: data)
    }

    private func fetchBillSummary() async throws -> BillSummaryResponse {
        let data = try await request(path: "/api/member/getBillSummary", method: "GET")
        try throwIfAPIError(data)
        return try decoder.decode(BillSummaryResponse.self, from: data)
    }

    private func fetchServiceStatus() async throws -> ServiceStatusResponse {
        let data = try await request(path: "/api/member/getServiceStatus", method: "GET")
        try throwIfAPIError(data)
        return try decoder.decode(ServiceStatusResponse.self, from: data)
    }

    private func request(path: String, method: String, body: Data? = nil) async throws -> Data {
        guard let url = URL(string: "https://www.iijmio.jp\(path)") else {
            throw IIJAPIClientError.invalidURL(path)
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw IIJAPIClientError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let bodySnippet = String(data: data, encoding: .utf8) ?? "(non-UTF8 body)"
            print("[IIJAPI] HTTP \(httpResponse.statusCode) for \(method) \(url.absoluteString)\nRequest headers: \(request.allHTTPHeaderFields ?? [:])\nResponse: \(bodySnippet.prefix(500))")
            throw IIJAPIClientError.httpError(httpResponse.statusCode)
        }
        return data
    }

    private func performWithAutoLogin<T>(credentials: Credentials, operation: () async throws -> T) async throws -> T {
        try await ensureSession(credentials: credentials)

        do {
            return try await operation()
        } catch {
            guard shouldRetryWithLogin(for: error) else {
                throw error
            }
        }

        invalidateSession()
        try await ensureSession(credentials: credentials)
        return try await operation()
    }

    private func shouldRetryWithLogin(for error: Error) -> Bool {
        if case IIJAPIClientError.httpError(let code) = error {
            return code == 401 || code == 403 || code == 419
        }

        let nsError = error as NSError
        if nsError.domain == "IIJAPI" {
            let description = nsError.userInfo[NSLocalizedDescriptionKey] as? String ?? nsError.localizedDescription
            let lowered = description.lowercased()
            if lowered.contains("login") || lowered.contains("unauthorized") || description.contains("ログイン") {
                return true
            }
            // ERROR_CODE_032 is returned when the session cookie is missing or expired.
            if description.contains("ERROR_CODE_032") || description.contains("ERROR_CODE_023") {
                return true
            }
        }

        return false
    }

    private func ensureSession(credentials: Credentials) async throws {
        if let current = activeCredentials, current != credentials {
            invalidateSession()
        }

        guard !hasValidSession else { return }

        try await establishSession(credentials: credentials)
        activeCredentials = credentials
        hasValidSession = true
    }

    private func establishSession(credentials: Credentials) async throws {
        try await warmupWAF()
        try await login(credentials: credentials)
    }

    private func warmupWAF() async throws {
        _ = try await request(path: "/auth/login/", method: "GET")
    }

    private func invalidateSession() {
        hasValidSession = false
    }

    private func decodeAPIErrorIfNeeded(from data: Data) throws -> String? {
        guard let envelope = try? decoder.decode(APIErrorEnvelope.self, from: data) else {
            return nil
        }
        return envelope.error
    }

    private func throwIfAPIError(_ data: Data) throws {
        if let errorCode = try decodeAPIErrorIfNeeded(from: data) {
            throw NSError(domain: "IIJAPI", code: 0, userInfo: [NSLocalizedDescriptionKey: "APIエラー: \(errorCode)"])
        }
    }
}
