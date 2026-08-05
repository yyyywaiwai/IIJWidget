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

    private let baseURL = URL(string: "https://gapi.iijmio.jp")!
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private let tokenStore = MyIIJmioTokenStore()
    private let debugStore = DebugResponseStore.shared
    private let debugResponsesEnabled: Bool

    init(debugResponsesEnabled: Bool = true) {
        self.debugResponsesEnabled = debugResponsesEnabled
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 45
        configuration.timeoutIntervalForResource = 60
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpShouldSetCookies = false
        session = URLSession(configuration: configuration)
    }

    func fetchAllUsingExistingSession(forceUpdate: Bool = false) async throws -> AggregatePayload {
        let storedSession = try loadStoredSession()
        return try await fetchAll(session: storedSession, forceUpdate: forceUpdate)
    }

    func fetchAll(credentials: Credentials, forceUpdate: Bool = false) async throws -> AggregatePayload {
        let authenticatedSession = try await login(credentials: credentials)
        return try await fetchAll(session: authenticatedSession, forceUpdate: forceUpdate)
    }

    func fetchTopUsingExistingSession(forceUpdate: Bool = false) async throws -> MemberTopResponse {
        let storedSession = try loadStoredSession()
        return try await fetchTop(session: storedSession, forceUpdate: forceUpdate)
    }

    func fetchTop(credentials: Credentials, forceUpdate: Bool = false) async throws -> MemberTopResponse {
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
        let response: GAPILoginResponse = try await request(
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
        try tokenStore.save(authenticatedSession)
        return authenticatedSession
    }

    func fetchAll(
        session authenticatedSession: MyIIJmioSession,
        forceUpdate: Bool = false
    ) async throws -> AggregatePayload {
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
                query: query
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
    ) async throws -> MemberTopResponse {
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
                URLQueryItem(name: "dataDetailFlag", value: "0"),
                URLQueryItem(name: "mainLineServiceCode", value: mainLineServiceCode)
            ],
            forceUpdate: forceUpdate
        )
        return MyIIJmioPayloadMapper.top(dataTraffic: dataTraffic, usageFee: nil)
    }

    private func authenticatedRequest<Response: Decodable>(
        session authenticatedSession: MyIIJmioSession,
        path: String,
        query: [URLQueryItem] = [],
        forceUpdate: Bool = false
    ) async throws -> Response {
        try await request(
            path: path,
            method: "GET",
            authorization: "Bearer \(authenticatedSession.token),appVersion=\(Self.officialAppVersion)",
            query: query,
            forceUpdate: forceUpdate,
            body: Optional<EmptyRequestBody>.none
        )
    }

    private func request<Response: Decodable, Body: Encodable>(
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

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw error
        }
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
            if debugResponsesEnabled {
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
        guard debugResponsesEnabled else { return }
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

struct GAPILoginRequest: Encodable {
    let loginId: String
    let password: String
}

struct GAPILoginResponse: Decodable {
    let mioId: String
    let token: String
    let contractorName: String?
}

struct GAPILineInfoResponse: Decodable {
    let mioId: String?
    let lineInfo: GAPILineInfo
}

struct GAPILineInfo: Decodable {
    let hdcList: [GAPILineInfoLine]
    let hddList: [GAPILineInfoLine]

    var allLines: [GAPILineInfoLine] { hdcList + hddList }

    private enum CodingKeys: String, CodingKey {
        case hdcList
        case hddList
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hdcList = try container.decodeIfPresent([GAPILineInfoLine].self, forKey: .hdcList) ?? []
        hddList = try container.decodeIfPresent([GAPILineInfoLine].self, forKey: .hddList) ?? []
    }
}

struct GAPILineInfoLine: Decodable {
    let serviceCode: String?
    let lineServiceCode: String?
    let groupServiceCode: String?
    let planName: String?
    let telNo: String?
    let number: String?
}

struct GAPIDataTrafficResponse: Decodable {
    let mioId: String?
    let dataTraffic: GAPIDataTraffic
}

struct GAPIDataTraffic: Decodable {
    let hdcList: [GAPITrafficLine]
    let hddList: [GAPITrafficGroup]
    let mainHdd: [GAPITrafficGroup]

    var resolvedLines: [GAPIResolvedTrafficLine] {
        let hdcLines = hdcList.map { GAPIResolvedTrafficLine(line: $0, parentServiceCode: nil, parentPlanCode: nil) }
        let groupedLines = (hddList + mainHdd).flatMap { group in
            group.lineServiceCodeList.map {
                GAPIResolvedTrafficLine(
                    line: $0,
                    parentServiceCode: group.serviceCode,
                    parentPlanCode: group.planCode
                )
            }
        }
        return hdcLines + groupedLines
    }

    private enum CodingKeys: String, CodingKey {
        case hdcList
        case hddList
        case mainHdd
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hdcList = try container.decodeIfPresent([GAPITrafficLine].self, forKey: .hdcList) ?? []
        hddList = try container.decodeIfPresent([GAPITrafficGroup].self, forKey: .hddList) ?? []
        mainHdd = try container.decodeIfPresent([GAPITrafficGroup].self, forKey: .mainHdd) ?? []
    }
}

struct GAPITrafficGroup: Decodable {
    let serviceCode: String?
    let planCode: String?
    let lineServiceCodeList: [GAPITrafficLine]

    private enum CodingKeys: String, CodingKey {
        case serviceCode
        case planCode
        case lineServiceCodeList
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        serviceCode = try container.decodeIfPresent(String.self, forKey: .serviceCode)
        planCode = try container.decodeIfPresent(String.self, forKey: .planCode)
        lineServiceCodeList = try container.decodeIfPresent([GAPITrafficLine].self, forKey: .lineServiceCodeList) ?? []
    }
}

struct GAPITrafficLine: Decodable {
    let serviceCode: String?
    let lineServiceCode: String?
    let groupServiceCode: String?
    let planName: String?
    let telNo: String?
    let msIsdn: String?
    let couponValue: Double?
    let expireList: [GAPIExpireEntry]
    let thisMonthDataList: GAPIThisMonthData?
    let lastSevenDaysDataList: GAPILastSevenDaysData?

    private enum CodingKeys: String, CodingKey {
        case serviceCode
        case lineServiceCode
        case groupServiceCode
        case planName
        case telNo
        case msIsdn
        case couponValue
        case expireList
        case thisMonthDataList
        case lastSevenDaysDataList
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        serviceCode = try container.decodeIfPresent(String.self, forKey: .serviceCode)
        lineServiceCode = try container.decodeIfPresent(String.self, forKey: .lineServiceCode)
        groupServiceCode = try container.decodeIfPresent(String.self, forKey: .groupServiceCode)
        planName = try container.decodeIfPresent(String.self, forKey: .planName)
        telNo = try container.decodeIfPresent(String.self, forKey: .telNo)
        msIsdn = try container.decodeIfPresent(String.self, forKey: .msIsdn)
        couponValue = try container.decodeLossyDoubleIfPresent(forKey: .couponValue)
        expireList = try container.decodeIfPresent([GAPIExpireEntry].self, forKey: .expireList) ?? []
        thisMonthDataList = try container.decodeIfPresent(GAPIThisMonthData.self, forKey: .thisMonthDataList)
        lastSevenDaysDataList = try container.decodeIfPresent(GAPILastSevenDaysData.self, forKey: .lastSevenDaysDataList)
    }
}

struct GAPIResolvedTrafficLine {
    let line: GAPITrafficLine
    let parentServiceCode: String?
    let parentPlanCode: String?

    var serviceCode: String? { line.serviceCode ?? parentServiceCode }
    var lineServiceCode: String? { line.lineServiceCode }
    var planName: String? { line.planName ?? parentPlanCode }
}

struct GAPIExpireEntry: Decodable {
    let expireYear: String?
    let expireMonth: String?
    let remainingDataTraffic: Double?
    let dataUnit: String?

    private enum CodingKeys: String, CodingKey {
        case expireYear
        case expireMonth
        case remainingDataTraffic
        case dataUnit
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        expireYear = try container.decodeLossyStringIfPresent(forKey: .expireYear)
        expireMonth = try container.decodeLossyStringIfPresent(forKey: .expireMonth)
        remainingDataTraffic = try container.decodeLossyDoubleIfPresent(forKey: .remainingDataTraffic)
        dataUnit = try container.decodeIfPresent(String.self, forKey: .dataUnit)
    }
}

struct GAPIThisMonthData: Decodable {
    let availableDataTraffic: Double?
    let availableDataTrafficUnit: String?
    let maxDataTraffic: Double?
    let maxDataTrafficUnit: String?
    let couponStatus: Int?
    let regulationStatus: Int?
    let dataShare: Int?
    let usePeriod: String?

    private enum CodingKeys: String, CodingKey {
        case availableDataTraffic
        case availableDataTrafficUnit
        case maxDataTraffic
        case maxDataTrafficUnit
        case couponStatus
        case regulationStatus
        case dataShare
        case usePeriod
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        availableDataTraffic = try container.decodeLossyDoubleIfPresent(forKey: .availableDataTraffic)
        availableDataTrafficUnit = try container.decodeIfPresent(String.self, forKey: .availableDataTrafficUnit)
        maxDataTraffic = try container.decodeLossyDoubleIfPresent(forKey: .maxDataTraffic)
        maxDataTrafficUnit = try container.decodeIfPresent(String.self, forKey: .maxDataTrafficUnit)
        couponStatus = try container.decodeLossyIntIfPresent(forKey: .couponStatus)
        regulationStatus = try container.decodeLossyIntIfPresent(forKey: .regulationStatus)
        dataShare = try container.decodeLossyIntIfPresent(forKey: .dataShare)
        usePeriod = try container.decodeLossyStringIfPresent(forKey: .usePeriod)
    }
}

struct GAPILastSevenDaysData: Decodable {
    let lastSevenDays: String?
    let lastSevenDaysDataHighUnit: String?
    let lastSevenDaysDataLowUnit: String?
    let dailyDataList: [GAPILastSevenDaysEntry]

    private enum CodingKeys: String, CodingKey {
        case lastSevenDays
        case lastSevenDaysDataHighUnit
        case lastSevenDaysDataLowUnit
        case dailyDataList
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lastSevenDays = try container.decodeIfPresent(String.self, forKey: .lastSevenDays)
        lastSevenDaysDataHighUnit = try container.decodeIfPresent(String.self, forKey: .lastSevenDaysDataHighUnit)
        lastSevenDaysDataLowUnit = try container.decodeIfPresent(String.self, forKey: .lastSevenDaysDataLowUnit)
        dailyDataList = try container.decodeIfPresent([GAPILastSevenDaysEntry].self, forKey: .dailyDataList) ?? []
    }
}

struct GAPILastSevenDaysEntry: Decodable {
    let month: String?
    let date: String?
    let dayOfWeek: String?
    let high: String?
    let low: String?
}

struct GAPIContractResponse: Decodable {
    let mioId: String?
    let contract: GAPIContract
}

struct GAPIContract: Decodable {
    let hdcList: [GAPIContractLine]
    let hddList: [GAPIContractLine]

    var allLines: [GAPIContractLine] { hdcList + hddList }

    private enum CodingKeys: String, CodingKey {
        case hdcList
        case hddList
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hdcList = try container.decodeIfPresent([GAPIContractLine].self, forKey: .hdcList) ?? []
        hddList = try container.decodeIfPresent([GAPIContractLine].self, forKey: .hddList) ?? []
    }
}

struct GAPIContractLine: Decodable {
    let serviceCode: String?
    let lineServiceCode: String?
    let groupServiceCode: String?
    let planName: String?
    let telNo: String?
    let serviceStatus: String?
    let chargePlan: String?
    let eSim: Int?

    private enum CodingKeys: String, CodingKey {
        case serviceCode
        case lineServiceCode
        case groupServiceCode
        case planName
        case telNo
        case serviceStatus
        case chargePlan
        case eSim
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        serviceCode = try container.decodeIfPresent(String.self, forKey: .serviceCode)
        lineServiceCode = try container.decodeIfPresent(String.self, forKey: .lineServiceCode)
        groupServiceCode = try container.decodeIfPresent(String.self, forKey: .groupServiceCode)
        planName = try container.decodeIfPresent(String.self, forKey: .planName)
        telNo = try container.decodeIfPresent(String.self, forKey: .telNo)
        serviceStatus = try container.decodeLossyStringIfPresent(forKey: .serviceStatus)
        chargePlan = try container.decodeLossyStringIfPresent(forKey: .chargePlan)
        eSim = try container.decodeLossyIntIfPresent(forKey: .eSim)
    }
}

struct GAPIUsageFeeResponse: Decodable {
    let billingMonth: String?
    let billingPeriod: String?
    let billingTotalAmount: String?
    let billingSummary: [GAPIBillingSummary]

    private enum CodingKeys: String, CodingKey {
        case billingMonth
        case billingPeriod
        case billingTotalAmount
        case billingSummary
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        billingMonth = try container.decodeLossyStringIfPresent(forKey: .billingMonth)
        billingPeriod = try container.decodeLossyStringIfPresent(forKey: .billingPeriod)
        billingTotalAmount = try container.decodeLossyStringIfPresent(forKey: .billingTotalAmount)
        billingSummary = try container.decodeIfPresent([GAPIBillingSummary].self, forKey: .billingSummary) ?? []
    }
}

struct GAPIBillingSummary: Decodable {
    let billingMonth: String?
    let billingNo: String?
    let billingTotalAmount: String?
    let detailDataList: [GAPIBillingDetailSection]
    let remarksList: [String]

    private enum CodingKeys: String, CodingKey {
        case billingMonth
        case billingNo
        case billingTotalAmount
        case detailDataList
        case remarksList
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        billingMonth = try container.decodeLossyStringIfPresent(forKey: .billingMonth)
        billingNo = try container.decodeLossyStringIfPresent(forKey: .billingNo)
        billingTotalAmount = try container.decodeLossyStringIfPresent(forKey: .billingTotalAmount)
        detailDataList = try container.decodeIfPresent([GAPIBillingDetailSection].self, forKey: .detailDataList) ?? []
        remarksList = try container.decodeIfPresent([String].self, forKey: .remarksList) ?? []
    }
}

struct GAPIBillingDetailSection: Decodable {
    let label: String?
    let subTotal: Double?
    let detailItemList: [GAPIBillingDetailItem]

    private enum CodingKeys: String, CodingKey {
        case label
        case subTotal
        case detailItemList
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        subTotal = try container.decodeLossyDoubleIfPresent(forKey: .subTotal)
        detailItemList = try container.decodeIfPresent([GAPIBillingDetailItem].self, forKey: .detailItemList) ?? []
    }
}

struct GAPIBillingDetailItem: Decodable {
    let title: String?
    let amount: Double?
    let quantity: String?
    let unitPrice: Double?
    let remarks: String?

    private enum CodingKeys: String, CodingKey {
        case title
        case amount
        case quantity
        case unitPrice
        case remarks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        amount = try container.decodeLossyDoubleIfPresent(forKey: .amount)
        quantity = try container.decodeLossyStringIfPresent(forKey: .quantity)
        unitPrice = try container.decodeLossyDoubleIfPresent(forKey: .unitPrice)
        remarks = try container.decodeIfPresent(String.self, forKey: .remarks)
    }
}

struct GAPIPastDataTrafficResponse: Decodable {
    let serviceCode: String?
    let lastFiveMonthDataUnit: String?
    let lastFiveMonthInfo: [GAPIPastMonthEntry]
    let thisMonthInfo: GAPIThisMonthInfo?
    let thisMonthDailyInfo: [GAPIPastDayEntry]

    private enum CodingKeys: String, CodingKey {
        case serviceCode
        case lastFiveMonthDataUnit
        case lastFiveMonthInfo
        case thisMonthInfo
        case thisMonthDailyInfo
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        serviceCode = try container.decodeIfPresent(String.self, forKey: .serviceCode)
        lastFiveMonthDataUnit = try container.decodeIfPresent(String.self, forKey: .lastFiveMonthDataUnit)
        lastFiveMonthInfo = try container.decodeIfPresent([GAPIPastMonthEntry].self, forKey: .lastFiveMonthInfo) ?? []
        thisMonthInfo = try container.decodeIfPresent(GAPIThisMonthInfo.self, forKey: .thisMonthInfo)
        thisMonthDailyInfo = try container.decodeIfPresent([GAPIPastDayEntry].self, forKey: .thisMonthDailyInfo) ?? []
    }
}

struct GAPIPastMonthEntry: Decodable {
    let month: String?
    let dataTraffic: String?

    private enum CodingKeys: String, CodingKey {
        case month
        case dataTraffic
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        month = try container.decodeLossyStringIfPresent(forKey: .month)
        dataTraffic = try container.decodeLossyStringIfPresent(forKey: .dataTraffic)
    }
}

struct GAPIThisMonthInfo: Decodable {
    let month: String?
    let day: String?

    private enum CodingKeys: String, CodingKey {
        case month
        case day
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        month = try container.decodeLossyStringIfPresent(forKey: .month)
        day = try container.decodeLossyStringIfPresent(forKey: .day)
    }
}

struct GAPIPastDayEntry: Decodable {
    let date: String?
    let dayOfWeek: String?
    let dataTraffic: String?
    let dataTrafficUnit: String?

    private enum CodingKeys: String, CodingKey {
        case date
        case dayOfWeek
        case dataTraffic
        case dataTrafficUnit
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decodeLossyStringIfPresent(forKey: .date)
        dayOfWeek = try container.decodeLossyStringIfPresent(forKey: .dayOfWeek)
        dataTraffic = try container.decodeLossyStringIfPresent(forKey: .dataTraffic)
        dataTrafficUnit = try container.decodeIfPresent(String.self, forKey: .dataTrafficUnit)
    }
}

struct GAPIPastTrafficResult {
    let line: GAPIResolvedTrafficLine
    let response: GAPIPastDataTrafficResponse
}

enum MyIIJmioPayloadMapper {
    static func aggregatePayload(
        lineInfo: GAPILineInfoResponse,
        dataTraffic: GAPIDataTrafficResponse,
        contract: GAPIContractResponse,
        usageFee: GAPIUsageFeeResponse,
        pastTraffic: [GAPIPastTrafficResult],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> AggregatePayload {
        AggregatePayload(
            fetchedAt: now,
            top: top(dataTraffic: dataTraffic, usageFee: usageFee),
            bill: bill(usageFee: usageFee),
            serviceStatus: serviceStatus(contract: contract, dataTraffic: dataTraffic),
            monthlyUsage: monthlyUsage(from: pastTraffic, now: now, calendar: calendar),
            dailyUsage: dailyUsage(from: pastTraffic, now: now, calendar: calendar)
        )
    }

    static func top(
        dataTraffic: GAPIDataTrafficResponse,
        usageFee: GAPIUsageFeeResponse?
    ) -> MemberTopResponse {
        let services = dataTraffic.dataTraffic.resolvedLines.map { resolved in
            let line = resolved.line
            let current = line.thisMonthDataList
            let expireEntries = line.expireList.enumerated().map { index, entry in
                MemberTopResponse.ServiceInfo.CouponEntry(
                    adjustmentCoupon: false,
                    sequenceNo: index,
                    month: expirationMonth(year: entry.expireYear, month: entry.expireMonth),
                    couponValue: amountInGigabytes(entry.remainingDataTraffic, unit: entry.dataUnit)
                )
            }
            let fallbackCoupon: [MemberTopResponse.ServiceInfo.CouponEntry]
            if expireEntries.isEmpty {
                fallbackCoupon = [
                    MemberTopResponse.ServiceInfo.CouponEntry(
                        adjustmentCoupon: false,
                        sequenceNo: 0,
                        month: nil,
                        couponValue: amountInGigabytes(
                            current?.availableDataTraffic ?? line.couponValue,
                            unit: current?.availableDataTrafficUnit
                        )
                    )
                ]
            } else {
                fallbackCoupon = expireEntries
            }

            return MemberTopResponse.ServiceInfo(
                dataShareNotCovered: current?.dataShare == 0,
                serviceCode: resolved.serviceCode ?? resolved.lineServiceCode,
                totalCapacity: amountInGigabytes(current?.maxDataTraffic, unit: current?.maxDataTrafficUnit),
                dataShareExistence: current?.dataShare == 1,
                planName: resolved.planName,
                chargePlan: current?.maxDataTraffic.map { compactNumber($0) },
                serviceName: resolved.planName,
                phoneNo: line.telNo ?? line.msIsdn,
                couponData: fallbackCoupon
            )
        }
        let billSummary = usageFee.map {
            MemberTopResponse.BillSummary(
                amount: $0.billingTotalAmount,
                miowari: nil,
                month: $0.billingMonth
            )
        }
        let prefixes = Set(services.compactMap { $0.serviceCode.map { String($0.prefix(3)) } }).sorted()
        let hasVouchers = services.contains { ($0.remainingDataGB ?? 0) > 0 }
        let usagePeriod = dataTraffic.dataTraffic.resolvedLines.compactMap { $0.line.thisMonthDataList?.usePeriod }.first
        return MemberTopResponse(
            serviceInfoList: services,
            billSummary: billSummary,
            hasVouchers: hasVouchers,
            usagePeriod: usagePeriod,
            prefixList: prefixes
        )
    }

    static func bill(usageFee: GAPIUsageFeeResponse) -> BillSummaryResponse {
        let entries = usageFee.billingSummary.map { summary in
            BillSummaryResponse.BillEntry(
                billNoList: summary.billingNo.map { [$0] },
                month: normalizedYearMonth(summary.billingMonth),
                totalAmount: integerAmount(summary.billingTotalAmount),
                usedPoint: nil,
                isUnpaid: nil
            )
        }
        return BillSummaryResponse(billList: entries, isVoiceSim: nil, isImt: nil)
    }

    static func billDetail(
        entry: BillSummaryResponse.BillEntry,
        usageFee: GAPIUsageFeeResponse
    ) -> BillDetailResponse? {
        let expectedBillNumbers = Set(entry.billNoList ?? [])
        let expectedMonth = normalizedYearMonth(entry.month)
        guard let summary = usageFee.billingSummary.first(where: { candidate in
            if let number = candidate.billingNo, expectedBillNumbers.contains(number) {
                return true
            }
            return normalizedYearMonth(candidate.billingMonth) == expectedMonth
        }) else {
            return nil
        }

        let sections = summary.detailDataList.map { section in
            BillDetailResponse.Section(
                title: section.label ?? "請求明細",
                items: section.detailItemList.map { item in
                    BillDetailResponse.Item(
                        title: item.title ?? "明細",
                        detail: item.remarks,
                        quantityText: item.quantity,
                        unitPriceText: item.unitPrice.map(currencyText),
                        amountText: item.amount.map(currencyText)
                    )
                },
                subtotalText: section.subTotal.map(currencyText)
            )
        }
        let amount = integerAmount(summary.billingTotalAmount)
        return BillDetailResponse(
            monthText: formattedMonth(summary.billingMonth),
            totalAmountText: amount.map { currencyText(Double($0)) } ?? "-",
            totalAmount: amount,
            taxBreakdowns: [],
            sections: sections
        )
    }

    static func serviceStatus(
        contract: GAPIContractResponse,
        dataTraffic: GAPIDataTrafficResponse
    ) -> ServiceStatusResponse {
        let trafficLines = dataTraffic.dataTraffic.resolvedLines
        let statuses = trafficLines.map { trafficLine in
            let matchingContract = contract.contract.allLines.first { contractLine in
                if let lineServiceCode = trafficLine.lineServiceCode,
                   contractLine.lineServiceCode == lineServiceCode {
                    return true
                }
                return contractLine.serviceCode == trafficLine.serviceCode
            }
            let status = matchingContract?.serviceStatus
            let simType: String?
            if let isESIM = matchingContract?.eSim {
                simType = isESIM == 1 ? "eSIM" : "SIM"
            } else {
                simType = nil
            }
            return ServiceStatusResponse.ServiceStatus(
                simInfoList: [
                    ServiceStatusResponse.ServiceStatus.SimInfo(
                        simType: simType,
                        status: status
                    )
                ],
                serviceCodePrefix: trafficLine.serviceCode.map { String($0.prefix(3)) },
                stopDate: nil,
                planCode: matchingContract?.chargePlan ?? trafficLine.parentPlanCode,
                isBic: nil,
                status: status
            )
        }
        return ServiceStatusResponse(serviceInfoList: statuses, jmbNumberChangePossible: nil)
    }

    static func monthlyUsage(
        from results: [GAPIPastTrafficResult],
        now: Date,
        calendar: Calendar
    ) -> [MonthlyUsageService] {
        results.map { result in
            let entries = result.response.lastFiveMonthInfo.map { entry in
                MonthlyUsageEntry(
                    monthLabel: formattedYearMonth(entry.month, now: now, calendar: calendar),
                    highText: joinedAmount(entry.dataTraffic, unit: result.response.lastFiveMonthDataUnit),
                    lowText: nil,
                    note: nil,
                    hasData: entry.dataTraffic != nil
                )
            }
            return MonthlyUsageService(
                hdoCode: result.line.serviceCode ?? result.line.lineServiceCode ?? UUID().uuidString,
                titlePrimary: result.line.planName ?? "IIJmio回線",
                titleDetail: result.line.line.telNo ?? result.line.line.msIsdn,
                entries: entries
            )
        }
    }

    static func dailyUsage(
        from results: [GAPIPastTrafficResult],
        now: Date,
        calendar: Calendar
    ) -> [DailyUsageService] {
        results.map { result in
            let month = Int(result.response.thisMonthInfo?.month ?? "")
                ?? calendar.component(.month, from: now)
            let year = resolvedYear(forMonth: month, now: now, calendar: calendar)
            let entries = result.response.thisMonthDailyInfo.map { entry in
                let day = Int(entry.date ?? "") ?? 1
                return DailyUsageEntry(
                    dateLabel: String(format: "%04d年%02d月%02d日", year, month, day),
                    highText: joinedAmount(entry.dataTraffic, unit: entry.dataTrafficUnit),
                    lowText: nil,
                    note: entry.dayOfWeek,
                    hasData: entry.dataTraffic != nil
                )
            }
            return DailyUsageService(
                hdoCode: result.line.serviceCode ?? result.line.lineServiceCode ?? UUID().uuidString,
                titlePrimary: result.line.planName ?? "IIJmio回線",
                titleDetail: result.line.line.telNo ?? result.line.line.msIsdn,
                entries: entries
            )
        }
    }

    private static func amountInGigabytes(_ value: Double?, unit: String?) -> Double? {
        guard let value else { return nil }
        let normalized = unit?.uppercased() ?? "GB"
        if normalized.contains("TB") { return value * 1024 }
        if normalized.contains("MB") { return value / 1024 }
        if normalized.contains("KB") { return value / (1024 * 1024) }
        return value
    }

    private static func expirationMonth(year: String?, month: String?) -> String? {
        guard let year, let month, let monthValue = Int(month) else { return nil }
        return String(format: "%@%02d", year, monthValue)
    }

    nonisolated private static func compactNumber(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(value)
    }

    private static func integerAmount(_ raw: String?) -> Int? {
        guard let raw else { return nil }
        let digits = raw.filter(\.isNumber)
        return Int(digits)
    }

    private static func normalizedYearMonth(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let digits = raw.filter(\.isNumber)
        guard digits.count >= 5 else { return raw }
        let year = String(digits.prefix(4))
        let monthDigits = String(digits.dropFirst(4).prefix(2))
        guard let month = Int(monthDigits) else { return raw }
        return String(format: "%@%02d", year, month)
    }

    private static func formattedMonth(_ raw: String?) -> String {
        guard let normalized = normalizedYearMonth(raw), normalized.count >= 6 else {
            return raw ?? "-"
        }
        let year = normalized.prefix(4)
        let month = Int(normalized.suffix(2)) ?? 0
        return "\(year)年\(month)月"
    }

    private static func formattedYearMonth(_ rawMonth: String?, now: Date, calendar: Calendar) -> String {
        let month = Int(rawMonth ?? "") ?? calendar.component(.month, from: now)
        let year = resolvedYear(forMonth: month, now: now, calendar: calendar)
        return String(format: "%04d年%02d月", year, month)
    }

    private static func resolvedYear(forMonth month: Int, now: Date, calendar: Calendar) -> Int {
        let currentMonth = calendar.component(.month, from: now)
        let currentYear = calendar.component(.year, from: now)
        return month > currentMonth ? currentYear - 1 : currentYear
    }

    private static func joinedAmount(_ value: String?, unit: String?) -> String? {
        guard let value else { return nil }
        return value + (unit ?? "")
    }

    nonisolated private static func currencyText(_ value: Double) -> String {
        let formatted: String
        if value.rounded() == value {
            formatted = String(Int(value))
        } else {
            formatted = String(format: "%.2f", value)
                .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
        }
        return "\(formatted)円"
    }
}

private extension KeyedDecodingContainer {
    func decodeLossyStringIfPresent(forKey key: Key) throws -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return value.rounded() == value ? String(Int(value)) : String(value)
        }
        return nil
    }

    func decodeLossyDoubleIfPresent(forKey key: Key) throws -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Double(value.replacingOccurrences(of: ",", with: ""))
        }
        return nil
    }

    func decodeLossyIntIfPresent(forKey key: Key) throws -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Int(value)
        }
        return nil
    }
}
