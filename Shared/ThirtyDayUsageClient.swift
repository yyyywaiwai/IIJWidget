import Foundation

enum ThirtyDayUsageError: LocalizedError {
    case invalidCredentials
    case invalidSession
    case invalidURL(String)
    case invalidResponse
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "資格情報が設定されていません"
        case .invalidSession:
            return "有効なセッションが見つかりませんでした"
        case .invalidURL(let path):
            return "無効なURL: \(path)"
        case .invalidResponse:
            return "サーバーレスポンスを解釈できませんでした"
        case .httpError(let code):
            return "HTTPステータス \(code) で失敗しました"
        }
    }
}

/// キャンセル起因のエラー判定。`CancellationError` と URLSession の -999 を、
/// ラップされている場合も含めて見分ける。アプリ側とウィジェット側で共用する。
enum TaskCancellation {
    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        var current: NSError? = error as NSError
        while let nsError = current {
            if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
                return true
            }
            current = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return false
    }
}

struct APIErrorEnvelope: Decodable {
    let error: String?
}

final class ThirtyDayUsageClient {
    private let session: URLSession
    private let cookieStorage: HTTPCookieStorage
    private let decoder = JSONDecoder()
    private let debugStore = DebugResponseStore.shared
    private let debugResponsesEnabled: Bool
    private var hasValidSession = false
    private var activeCredentials: Credentials?

    init(debugResponsesEnabled: Bool = true) {
        self.debugResponsesEnabled = debugResponsesEnabled
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = true
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.httpMaximumConnectionsPerHost = 12
        let storage = debugResponsesEnabled
            ? HTTPCookieStorage.sharedCookieStorage(forGroupContainerIdentifier: AppGroup.identifier)
            : config.httpCookieStorage!
        cookieStorage = storage
        config.httpCookieStorage = storage
        config.sharedContainerIdentifier = AppGroup.identifier
        config.httpAdditionalHeaders = [
            "Accept": "application/json",
            "User-Agent": "IIJFetcher/1.0"
        ]
        session = URLSession(configuration: config)
    }

    /// 会員サイトは30日表だけに使用する。GAPIの代替取得経路は持たない。
    func fetchThirtyDays(credentials: Credentials? = nil) async throws -> [DailyUsageService] {
        if let credentials {
            guard !credentials.mioId.isEmpty, !credentials.password.isEmpty else {
                throw ThirtyDayUsageError.invalidCredentials
            }
            return try await performWithAutoLogin(credentials: credentials) {
                try await fetchDailyUsage()
            }
        }
        return try await fetchDailyUsage()
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
            throw NSError(
                domain: "IIJAPI",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: friendlyMessage(for: errorCode, context: .login)]
            )
        }
    }

    private func fetchDailyUsage() async throws -> [DailyUsageService] {
        let landingData = try await request(path: "/service/setup/hdc/viewdailydata/", method: "GET", contentType: nil)
        let landingHTMLString = String(data: landingData, encoding: .utf8)
        let landingHTML = landingHTMLString ?? DebugPrettyFormatter.utf8String(from: landingData)
        recordResponse(
            title: "日次利用量 ランディング",
            path: "/service/setup/hdc/viewdailydata/ [GET]",
            category: .scraping,
            rawText: landingHTML,
            formattedText: nil
        )
        guard let landingHTMLString else { throw ThirtyDayUsageError.invalidResponse }

        let landingParser = DataUsageHTMLParser(html: landingHTMLString)
        let landing = landingParser.extractLandingPageForms()
        guard !landing.forms.isEmpty else { throw ThirtyDayUsageError.invalidResponse }
        let forms = landing.forms
        var services: [DailyUsageService] = []

        for form in forms {
            do {
                guard let detailHTML = try await requestDailyDetailHTML(hdoCode: form.hdoCode, csrfToken: form.csrfToken) else {
                    throw ThirtyDayUsageError.invalidResponse
                }

                let detailParser = DataUsageHTMLParser(html: detailHTML)
                guard let service = detailParser.parseDailyService(hdoCode: form.hdoCode),
                      !service.entries.isEmpty else { throw ThirtyDayUsageError.invalidResponse }
                recordResponse(
                    title: "日次利用量 詳細 \(form.hdoCode)",
                    path: "/service/setup/hdc/viewdailydata/ [POST]",
                    category: .scraping,
                    rawText: detailHTML,
                    formattedText: DebugPrettyFormatter.prettyJSONString(service)
                )
                services.append(service)
            } catch {
                recordResponse(
                    title: "日次利用量 詳細 (取得失敗) \(form.hdoCode)",
                    path: "/service/setup/hdc/viewdailydata/ [POST]",
                    category: .scraping,
                    rawText: error.localizedDescription,
                    formattedText: nil
                )
                throw error
            }
        }

        return services
    }

    private func requestDailyDetailHTML(hdoCode: String, csrfToken: String) async throws -> String? {
        guard let body = formURLEncoded([
            "hdoCode": hdoCode,
            "_csrf": csrfToken
        ]) else { return nil }

        let response = try await request(
            path: "/service/setup/hdc/viewdailydata/",
            method: "POST",
            body: body,
            contentType: "application/x-www-form-urlencoded"
        )
        return String(data: response, encoding: .utf8)
    }

    private func formURLEncoded(_ parameters: [String: String]) -> Data? {
        var components = URLComponents()
        components.queryItems = parameters.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let query = components.percentEncodedQuery else { return nil }
        return query.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
    }

    private func request(path: String, method: String, body: Data? = nil, contentType: String? = "application/json") async throws -> Data {
        guard let url = URL(string: "https://www.iijmio.jp\(path)") else {
            throw ThirtyDayUsageError.invalidURL(path)
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        if let body {
            request.httpBody = body
            if let contentType {
                request.setValue(contentType, forHTTPHeaderField: "Content-Type")
            }
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ThirtyDayUsageError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let bodyText = DebugPrettyFormatter.utf8String(from: data)
            let category: DebugResponseRecord.Category = path.hasPrefix("/api/") ? .api : .scraping
            recordResponse(
                title: "HTTP \(httpResponse.statusCode) \(method)",
                path: path,
                category: category,
                rawText: bodyText,
                formattedText: nil
            )
            throw ThirtyDayUsageError.httpError(httpResponse.statusCode)
        }
        if let finalPath = httpResponse.url?.path,
           path.contains("viewdailydata"), finalPath.contains("login") {
            throw ThirtyDayUsageError.invalidSession
        }
        if path != "/api/member/login" { try throwIfAPIError(data) }
        return data
    }

    private func performWithAutoLogin<T>(credentials: Credentials, operation: () async throws -> T) async throws -> T {
        try await ensureSession(credentials: credentials)

        do {
            return try await operation()
        } catch {
            guard isAuthenticationError(error) else {
                throw error
            }
        }

        invalidateSession()
        try await ensureSession(credentials: credentials)
        return try await operation()
    }

    func isAuthenticationError(_ error: Error) -> Bool {
        if case ThirtyDayUsageError.invalidSession = error { return true }
        if case ThirtyDayUsageError.httpError(let code) = error {
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

    func clearPersistedSession() {
        hasValidSession = false
        activeCredentials = nil
        cookieStorage.cookies?.forEach { cookie in
            cookieStorage.deleteCookie(cookie)
        }
    }

    private func recordResponse(title: String, path: String, category: DebugResponseRecord.Category,
                                rawText: String, formattedText: String?) {
        guard debugResponsesEnabled else { return }
        debugStore.appendResponse(title: title, path: path, category: category,
                                  rawText: rawText, formattedText: formattedText)
    }

    private func decodeAPIErrorIfNeeded(from data: Data) throws -> String? {
        guard let envelope = try? decoder.decode(APIErrorEnvelope.self, from: data) else {
            return nil
        }
        return envelope.error
    }

    private func throwIfAPIError(_ data: Data) throws {
        if let errorCode = try decodeAPIErrorIfNeeded(from: data) {
            throw NSError(
                domain: "IIJAPI",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: friendlyMessage(for: errorCode, context: .general)]
            )
        }
    }

    private enum APIErrorContext {
        case login
        case general
    }

    private func friendlyMessage(for errorCode: String, context: APIErrorContext) -> String {
        switch errorCode {
        case "WARNING_CODE_008", "ERROR_CODE_008":
            if context == .login {
                return "ユーザー名またはパスワードが間違っています"
            }
        default:
            break
        }

        switch context {
        case .login:
            return "ログインエラー: \(errorCode)"
        case .general:
            return "APIエラー: \(errorCode)"
        }
    }

}
