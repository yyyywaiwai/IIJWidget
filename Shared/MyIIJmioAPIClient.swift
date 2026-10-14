import Foundation

enum MyIIJmioAPIError: LocalizedError {
    case invalidCredentials
    case invalidSession
    case invalidURL(String)
    case invalidResponse
    case forcedUpdate
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "MyIIJmio GAPI の資格情報が設定されていません"
        case .invalidSession:
            return "MyIIJmio GAPI の認証セッションが無効です"
        case .invalidURL(let path):
            return "MyIIJmio GAPI のURLが無効です: \(path)"
        case .invalidResponse:
            return "MyIIJmio GAPI のレスポンスを解釈できませんでした"
        case .forcedUpdate:
            return "MyIIJmio GAPI が公式アプリの更新を要求しています"
        case .httpError(let statusCode):
            return "MyIIJmio GAPI がHTTP \(statusCode)を返しました"
        }
    }
}

final class MyIIJmioAPIClient {
    static let officialAppVersion = "3.2.5"

    private let httpClient: GAPIHTTPClient
    private let tokenStore = MyIIJmioTokenStore()
    private let persistSession: Bool

    init(
        debugResponsesEnabled: Bool = true,
        persistSession: Bool = true,
        session: URLSession? = nil
    ) {
        self.httpClient = GAPIHTTPClient(debugResponsesEnabled: debugResponsesEnabled, session: session)
        self.persistSession = persistSession
    }

    func fetchAllUsingExistingSession(forceUpdate: Bool = false) async throws -> AggregatePayload {
        let storedSession = try loadStoredSession()
        return try await fetchAll(session: storedSession, forceUpdate: forceUpdate)
    }

    func fetchAll(credentials: Credentials, forceUpdate: Bool = false) async throws -> AggregatePayload {
        let authenticatedSession = try await login(credentials: credentials)
        return try await fetchAll(session: authenticatedSession, forceUpdate: forceUpdate)
    }

    func fetchTopUsingExistingSession(forceUpdate: Bool = false) async throws -> (top: TrafficSummary, dailyUsage: [DailyUsageService]) {
        let storedSession = try loadStoredSession()
        return try await fetchTop(session: storedSession, forceUpdate: forceUpdate)
    }

    func fetchTop(credentials: Credentials, forceUpdate: Bool = false) async throws -> (top: TrafficSummary, dailyUsage: [DailyUsageService]) {
        let authenticatedSession = try await login(credentials: credentials)
        return try await fetchTop(session: authenticatedSession, forceUpdate: forceUpdate)
    }

    func fetchBillDetailUsingExistingSession(entry: BillSummaryResponse.BillEntry) async throws -> BillDetailResponse {
        let storedSession = try loadStoredSession()
        return try await fetchBillDetail(entry: entry, session: storedSession)
    }

    func fetchBillDetail(entry: BillSummaryResponse.BillEntry, credentials: Credentials) async throws -> BillDetailResponse {
        let authenticatedSession = try await login(credentials: credentials)
        return try await fetchBillDetail(entry: entry, session: authenticatedSession)
    }

    private func fetchBillDetail(
        entry: BillSummaryResponse.BillEntry,
        session authenticatedSession: MyIIJmioSession
    ) async throws -> BillDetailResponse {
        let usageFee: GAPIUsageFeeResponse = try await authenticatedRequest(
            session: authenticatedSession,
            path: "/usageFee"
        )
        guard let detail = MyIIJmioPayloadMapper.billDetail(entry: entry, usageFee: usageFee) else {
            throw MyIIJmioAPIError.invalidResponse
        }
        return detail
    }

    func clearPersistedSession() {
        try? tokenStore.delete()
    }

    func isAuthenticationError(_ error: Error) -> Bool {
        if case MyIIJmioAPIError.invalidSession = error {
            return true
        }
        if case MyIIJmioAPIError.httpError(let statusCode) = error {
            return statusCode == 401 || statusCode == 403
        }
        return false
    }

    private func loadStoredSession() throws -> MyIIJmioSession {
        guard let stored = try tokenStore.load(), !stored.token.isEmpty else {
            throw MyIIJmioAPIError.invalidSession
        }
        guard stored.appVersion == Self.officialAppVersion else {
            try? tokenStore.delete()
            throw MyIIJmioAPIError.invalidSession
        }
        return stored
    }

    private func login(credentials: Credentials) async throws -> MyIIJmioSession {
        guard !credentials.mioId.isEmpty, !credentials.password.isEmpty else {
            throw MyIIJmioAPIError.invalidCredentials
        }

        let body = GAPILoginRequest(loginId: credentials.mioId, password: credentials.password)
        let response: GAPILoginResponse = try await httpClient.request(
            path: "/token",
            method: "POST",
            authorization: "appVersion=\(Self.officialAppVersion)",
            body: body
        )
        guard !response.token.isEmpty, !response.mioId.isEmpty else {
            throw MyIIJmioAPIError.invalidResponse
        }

        let authenticatedSession = MyIIJmioSession(
            token: response.token,
            mioId: response.mioId,
            contractorName: response.contractorName,
            appVersion: Self.officialAppVersion,
            createdAt: Date()
        )
        if persistSession { try tokenStore.save(authenticatedSession) }
        return authenticatedSession
    }

    func fetchAll(
        session authenticatedSession: MyIIJmioSession,
        forceUpdate: Bool = false
    ) async throws -> AggregatePayload {
        let (lineInfo, dataTraffic) = try await fetchTraffic(
            session: authenticatedSession,
            forceUpdate: forceUpdate
        )
        let contract: GAPIContractResponse = try await authenticatedRequest(
            session: authenticatedSession,
            path: "/contract"
        )
        let usageFee: GAPIUsageFeeResponse = try await authenticatedRequest(
            session: authenticatedSession,
            path: "/usageFee"
        )

        var pastTraffic: [GAPIPastTrafficResult] = []
        for line in dataTraffic.dataTraffic.resolvedLines {
            guard let serviceCode = line.serviceCode, !serviceCode.isEmpty else { continue }
            var query = [URLQueryItem(name: "serviceCode", value: serviceCode)]
            if !serviceCode.lowercased().hasPrefix("hdc"), let lineServiceCode = line.lineServiceCode {
                query.append(URLQueryItem(name: "lineServiceCode", value: lineServiceCode))
            }
            let response: GAPIPastDataTrafficResponse = try await authenticatedRequest(
                session: authenticatedSession,
                path: "/pastDataTraffic",
                query: query,
                forceUpdate: forceUpdate
            )
            pastTraffic.append(GAPIPastTrafficResult(line: line, response: response))
        }

        return MyIIJmioPayloadMapper.aggregatePayload(
            lineInfo: lineInfo,
            dataTraffic: dataTraffic,
            contract: contract,
            usageFee: usageFee,
            pastTraffic: pastTraffic
        )
    }

    private func fetchTop(
        session authenticatedSession: MyIIJmioSession,
        forceUpdate: Bool
    ) async throws -> (top: TrafficSummary, dailyUsage: [DailyUsageService]) {
        let (_, dataTraffic) = try await fetchTraffic(
            session: authenticatedSession,
            forceUpdate: forceUpdate
        )
        return (
            MyIIJmioPayloadMapper.top(dataTraffic: dataTraffic),
            MyIIJmioPayloadMapper.mergeRecentUsage([], dataTraffic: dataTraffic, now: Date(), calendar: UsageDateLabel.calendar)
        )
    }

    /// Both full refreshes and lightweight widget refreshes use identical line selection.
    private func fetchTraffic(
        session authenticatedSession: MyIIJmioSession,
        forceUpdate: Bool
    ) async throws -> (lineInfo: GAPILineInfoResponse, dataTraffic: GAPIDataTrafficResponse) {
        let lineInfo: GAPILineInfoResponse = try await authenticatedRequest(
            session: authenticatedSession,
            path: "/lineInfo",
            forceUpdate: forceUpdate
        )
        let mainLineServiceCode = lineInfo.lineInfo.allLines.first?.lineServiceCode
        let dataTraffic: GAPIDataTrafficResponse = try await authenticatedRequest(
            session: authenticatedSession,
            path: "/dataTraffic",
            query: [
                URLQueryItem(name: "dataDetailFlag", value: "1"),
                URLQueryItem(name: "mainLineServiceCode", value: mainLineServiceCode)
            ],
            forceUpdate: forceUpdate
        )
        return (lineInfo, dataTraffic)
    }

    private func authenticatedRequest<Response: Decodable>(
        session authenticatedSession: MyIIJmioSession,
        path: String,
        query: [URLQueryItem] = [],
        forceUpdate: Bool = false
    ) async throws -> Response {
        try await httpClient.get(
            path: path,
            authorization: "Bearer \(authenticatedSession.token),appVersion=\(Self.officialAppVersion)",
            query: query,
            forceUpdate: forceUpdate
        )
    }
}
