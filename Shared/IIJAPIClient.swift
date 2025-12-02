import Foundation

enum IIJAPIClientError: LocalizedError {
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

struct APIErrorEnvelope: Decodable {
    let error: String?
}

final class IIJAPIClient {
    private let session: URLSession
    private let cookieStorage: HTTPCookieStorage
    private let decoder = JSONDecoder()
    private let debugStore = DebugResponseStore.shared
    private var hasValidSession = false
    private var activeCredentials: Credentials?

    init() {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.httpMaximumConnectionsPerHost = 12
        let storage = HTTPCookieStorage.sharedCookieStorage(forGroupContainerIdentifier: AppGroup.identifier)
        cookieStorage = storage
        config.httpCookieStorage = storage
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
            try await buildAggregatePayload()
        }
    }

    func fetchUsingExistingSession() async throws -> AggregatePayload {
        do {
            let payload = try await buildAggregatePayload()
            hasValidSession = true
            return payload
        } catch {
            invalidateSession()
            if isAuthenticationError(error) {
                throw IIJAPIClientError.invalidSession
            }
            throw error
        }
    }

    func fetchBillDetail(entry: BillSummaryResponse.BillEntry) async throws -> BillDetailResponse {
        let html = try await requestBillDetailHTML(for: entry)
        guard let detail = BillDetailHTMLParser(html: html).parse() else {
            debugStore.appendResponse(
                title: "請求詳細 (パース失敗)",
                path: "/customer/bill/detail/",
                category: .scraping,
                rawText: html,
                formattedText: nil
            )
            throw IIJAPIClientError.invalidResponse
        }
        debugStore.appendResponse(
            title: "請求詳細 \(entry.formattedMonth)",
            path: "/customer/bill/detail/",
            category: .scraping,
            rawText: html,
            formattedText: DebugPrettyFormatter.prettyJSONString(detail)
        )
        return detail
    }

    func fetchBillDetail(entry: BillSummaryResponse.BillEntry, credentials: Credentials) async throws -> BillDetailResponse {
        try await performWithAutoLogin(credentials: credentials) {
            try await fetchBillDetail(entry: entry)
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
        do {
            let decoded = try decoder.decode(MemberTopResponse.self, from: data)
            recordAPIResponse(title: "member/top", path: "/api/member/top", rawData: data, model: decoded)
            return decoded
        } catch {
            recordAPIRawFailure(title: "member/top (decode失敗)", path: "/api/member/top", rawData: data)
            throw error
        }
    }

    private func fetchBillSummary() async throws -> BillSummaryResponse {
        let data = try await request(path: "/api/member/getBillSummary", method: "GET")
        try throwIfAPIError(data)
        do {
            let decoded = try decoder.decode(BillSummaryResponse.self, from: data)
            recordAPIResponse(title: "getBillSummary", path: "/api/member/getBillSummary", rawData: data, model: decoded)
            return decoded
        } catch {
            recordAPIRawFailure(title: "getBillSummary (decode失敗)", path: "/api/member/getBillSummary", rawData: data)
            throw error
        }
    }

    private func fetchServiceStatus() async throws -> ServiceStatusResponse {
        let data = try await request(path: "/api/member/getServiceStatus", method: "GET")
        try throwIfAPIError(data)
        do {
            let decoded = try decoder.decode(ServiceStatusResponse.self, from: data)
            recordAPIResponse(title: "getServiceStatus", path: "/api/member/getServiceStatus", rawData: data, model: decoded)
            return decoded
        } catch {
            recordAPIRawFailure(title: "getServiceStatus (decode失敗)", path: "/api/member/getServiceStatus", rawData: data)
            throw error
        }
    }

    private func fetchMonthlyUsage() async throws -> [MonthlyUsageService] {
        let landingData = try await request(path: "/service/setup/hdc/viewmonthlydata/", method: "GET", contentType: nil)
        let landingHTMLString = String(data: landingData, encoding: .utf8)
        let landingHTML = landingHTMLString ?? DebugPrettyFormatter.utf8String(from: landingData)
        debugStore.appendResponse(
            title: "月次利用量 ランディング",
            path: "/service/setup/hdc/viewmonthlydata/ [GET]",
            category: .scraping,
            rawText: landingHTML,
            formattedText: nil
        )
        guard let landingHTMLString else { return [] }

        let landingParser = DataUsageHTMLParser(html: landingHTMLString)
        let landing = landingParser.extractLandingPageForms()
        guard !landing.forms.isEmpty else { return [] }

        let forms = landing.forms
        let servicesByCode = try await withThrowingTaskGroup(of: (String, MonthlyUsageService?).self) { group in
            for form in forms {
                group.addTask {
                    guard let body = self.formURLEncoded([
                        "hdoCode": form.hdoCode,
                        "_csrf": form.csrfToken
                    ]) else {
                        return (form.hdoCode, nil)
                    }

                    let response = try await self.request(
                        path: "/service/setup/hdc/viewmonthlydata/",
                        method: "POST",
                        body: body,
                        contentType: "application/x-www-form-urlencoded"
                    )
                    let detailHTML = String(data: response, encoding: .utf8) ?? DebugPrettyFormatter.utf8String(from: response)
                    let detailParser = DataUsageHTMLParser(html: detailHTML)
                    let service = detailParser.parseMonthlyService(hdoCode: form.hdoCode)
                    self.debugStore.appendResponse(
                        title: "月次利用量 詳細 \(form.hdoCode)",
                        path: "/service/setup/hdc/viewmonthlydata/ [POST]",
                        category: .scraping,
                        rawText: detailHTML,
                        formattedText: service.flatMap { DebugPrettyFormatter.prettyJSONString($0) }
                    )
                    return (form.hdoCode, service)
                }
            }

            var collected: [String: MonthlyUsageService] = [:]
            for try await (code, service) in group {
                if let service {
                    collected[code] = service
                }
            }
            return collected
        }

        return forms.compactMap { servicesByCode[$0.hdoCode] }
    }

    private func fetchDailyUsage() async throws -> [DailyUsageService] {
        let landingData = try await request(path: "/service/setup/hdc/viewdailydata/", method: "GET", contentType: nil)
        let landingHTMLString = String(data: landingData, encoding: .utf8)
        let landingHTML = landingHTMLString ?? DebugPrettyFormatter.utf8String(from: landingData)
        debugStore.appendResponse(
            title: "日次利用量 ランディング",
            path: "/service/setup/hdc/viewdailydata/ [GET]",
            category: .scraping,
            rawText: landingHTML,
            formattedText: nil
        )
        guard let landingHTMLString else { return [] }

        let landingParser = DataUsageHTMLParser(html: landingHTMLString)
        let landing = landingParser.extractLandingPageForms()
        let previewServices = landingParser.previewDailyServices(for: landing.forms)
        guard !landing.forms.isEmpty else { return [] }

        let forms = landing.forms
        let servicesByCode = try await withThrowingTaskGroup(of: (String, DailyUsageService?).self) { group in
            for form in forms {
                group.addTask {
                    guard let detailHTML = try await self.requestDailyDetailHTML(hdoCode: form.hdoCode, csrfToken: form.csrfToken) else {
                        return (form.hdoCode, nil)
                    }

                    let detailParser = DataUsageHTMLParser(html: detailHTML)
                    let baseService = detailParser.parseDailyService(hdoCode: form.hdoCode)
                    let merged = baseService.map { self.mergeDailyServices(primary: $0, overlay: previewServices[form.hdoCode]) }
                    self.debugStore.appendResponse(
                        title: "日次利用量 詳細 \(form.hdoCode)",
                        path: "/service/setup/hdc/viewdailydata/ [POST]",
                        category: .scraping,
                        rawText: detailHTML,
                        formattedText: merged.flatMap { DebugPrettyFormatter.prettyJSONString($0) }
                    )
                    return (form.hdoCode, merged)
                }
            }

            var collected: [String: DailyUsageService] = [:]
            for try await (code, service) in group {
                if let service {
                    collected[code] = service
                }
            }
            return collected
        }

        return forms.compactMap { servicesByCode[$0.hdoCode] }
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

    private func mergeDailyServices(primary: DailyUsageService, overlay: DailyUsageService?) -> DailyUsageService {
        guard let overlay else { return primary }
        var seenLabels = Set(primary.entries.map { $0.id })
        var mergedEntries = primary.entries

        for entry in overlay.entries.reversed() {
            if !seenLabels.contains(entry.id) {
                mergedEntries.insert(entry, at: 0)
                seenLabels.insert(entry.id)
            }
        }

        return DailyUsageService(
            hdoCode: primary.hdoCode,
            titlePrimary: primary.titlePrimary,
            titleDetail: primary.titleDetail,
            entries: mergedEntries
        )
    }

    private func formURLEncoded(_ parameters: [String: String]) -> Data? {
        var components = URLComponents()
        components.queryItems = parameters.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let query = components.percentEncodedQuery else { return nil }
        return query.data(using: .utf8)
    }

    private func request(path: String, method: String, body: Data? = nil, contentType: String? = "application/json") async throws -> Data {
        guard let url = URL(string: "https://www.iijmio.jp\(path)") else {
            throw IIJAPIClientError.invalidURL(path)
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
            throw IIJAPIClientError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let bodySnippet = String(data: data, encoding: .utf8) ?? "(non-UTF8 body)"
            print("[IIJAPI] HTTP \(httpResponse.statusCode) for \(method) \(url.absoluteString)\nRequest headers: \(request.allHTTPHeaderFields ?? [:])\nResponse: \(bodySnippet.prefix(500))")
            throw IIJAPIClientError.httpError(httpResponse.statusCode)
        }
        return data
    }

    private func requestBillDetailHTML(for entry: BillSummaryResponse.BillEntry) async throws -> String {
        guard let billNos = entry.billNoList, !billNos.isEmpty else {
            throw IIJAPIClientError.invalidResponse
        }
        guard let body = formURLEncodedArray(name: "billNoList", values: billNos) else {
            throw IIJAPIClientError.invalidResponse
        }
        let data = try await request(
            path: "/customer/bill/detail/",
            method: "POST",
            body: body,
            contentType: "application/x-www-form-urlencoded"
        )
        guard let html = String(data: data, encoding: .utf8) else {
            throw IIJAPIClientError.invalidResponse
        }
        if html.contains("システムエラー") {
            throw NSError(domain: "IIJAPI", code: 0, userInfo: [NSLocalizedDescriptionKey: "請求明細の取得中にエラーが発生しました"])
        }
        return html
    }

    private func formURLEncodedArray(name: String, values: [String]) -> Data? {
        guard !values.isEmpty else { return nil }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._* ")
        var segments: [String] = []
        for value in values {
            guard var encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
            encoded = encoded.replacingOccurrences(of: " ", with: "+")
            segments.append("\(name)=\(encoded)")
        }
        return segments.joined(separator: "&").data(using: .utf8)
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

    func clearPersistedSession() {
        hasValidSession = false
        activeCredentials = nil
        cookieStorage.cookies?.forEach { cookie in
            cookieStorage.deleteCookie(cookie)
        }
    }

    private func buildAggregatePayload() async throws -> AggregatePayload {
        async let top = fetchTop()
        async let bill = fetchBillSummary()
        async let status = fetchServiceStatus()
        async let usage = fetchMonthlyUsage()
        async let daily = fetchDailyUsage()
        return AggregatePayload(
            fetchedAt: Date(),
            top: try await top,
            bill: try await bill,
            serviceStatus: try await status,
            monthlyUsage: try await usage,
            dailyUsage: try await daily
        )
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

    private func recordAPIResponse<T: Encodable>(title: String, path: String, rawData: Data, model: T) {
        let rawText = DebugPrettyFormatter.utf8String(from: rawData)
        let formatted = DebugPrettyFormatter.prettyJSONString(model)
        debugStore.appendResponse(
            title: title,
            path: path,
            category: .api,
            rawText: rawText,
            formattedText: formatted
        )
    }

    private func recordAPIRawFailure(title: String, path: String, rawData: Data) {
        let rawText = DebugPrettyFormatter.utf8String(from: rawData)
        debugStore.appendResponse(
            title: title,
            path: path,
            category: .api,
            rawText: rawText,
            formattedText: nil
        )
    }
}
