import Foundation

struct CLIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct Credentials {
    let mioId: String
    let password: String
}

enum Command: String, CaseIterable {
    case top
    case bill
    case status
    case all
    case usage
    case daily
    case billDetail = "bill-detail"
}

struct CLIOptions {
    let credentials: Credentials
    let command: Command
    let billDetailBillNos: [String]
    let billDetailMonth: String?
}

struct APIErrorEnvelope: Decodable {
    let error: String?
}

struct MemberTopResponse: Codable {
    struct ServiceInfo: Codable {
        struct CouponEntry: Codable {
            let adjustmentCoupon: Bool?
            let sequenceNo: Int?
            let month: String?
            let couponValue: Double?
        }

        let dataShareNotCovered: Bool?
        let serviceCode: String?
        let totalCapacity: Double?
        let dataShareExistence: Bool?
        let planName: String?
        let chargePlan: String?
        let serviceName: String?
        let phoneNo: String?
        let couponData: [CouponEntry]?
    }

    struct BillSummary: Codable {
        let amount: String?
        let miowari: String?
        let month: String?
    }

    let serviceInfoList: [ServiceInfo]
    let billSummary: BillSummary?
    let hasVouchers: Bool?
    let usagePeriod: String?
    let prefixList: [String]?
}

struct BillSummaryResponse: Codable {
    struct BillEntry: Codable {
        let billNoList: [String]?
        let month: String?
        let totalAmount: Int?
        let usedPoint: Int?
        let isUnpaid: Bool?
    }

    let billList: [BillEntry]
    let isVoiceSim: Bool?
    let isImt: Bool?
}

struct BillDetailResponse: Codable {
    struct TaxBreakdown: Codable, Identifiable {
        let label: String
        let amountText: String
        let taxLabel: String?
        let taxAmountText: String?

        var id: String { label + (taxLabel ?? "") }
    }

    struct Section: Codable, Identifiable {
        let title: String
        let items: [Item]
        let subtotalText: String?

        var id: String { title + (subtotalText ?? "") }
    }

    struct Item: Codable, Identifiable {
        let title: String
        let detail: String?
        let quantityText: String?
        let unitPriceText: String?
        let amountText: String?

        var id: String {
            [title, detail, amountText].compactMap { $0 }.joined(separator: "|")
        }
    }

    let monthText: String
    let totalAmountText: String
    let totalAmount: Int?
    let taxBreakdowns: [TaxBreakdown]
    let sections: [Section]
}

struct ServiceStatusResponse: Codable {
    struct ServiceStatus: Codable {
        struct SimInfo: Codable {
            let simType: String?
            let status: String?
        }

        let simInfoList: [SimInfo]?
        let serviceCodePrefix: String?
        let stopDate: String?
        let planCode: String?
        let isBic: Bool?
        let status: String?
    }

    let serviceInfoList: [ServiceStatus]
    let jmbNumberChangePossible: Bool?
}

struct AggregatePayload: Codable {
    let fetchedAt: Date
    let top: MemberTopResponse
    let bill: BillSummaryResponse
    let serviceStatus: ServiceStatusResponse
    let monthlyUsage: [MonthlyUsageService]
    let dailyUsage: [DailyUsageService]

    private enum CodingKeys: String, CodingKey {
        case fetchedAt
        case top
        case bill
        case serviceStatus
        case monthlyUsage
        case dailyUsage
    }

    init(
        fetchedAt: Date,
        top: MemberTopResponse,
        bill: BillSummaryResponse,
        serviceStatus: ServiceStatusResponse,
        monthlyUsage: [MonthlyUsageService],
        dailyUsage: [DailyUsageService]
    ) {
        self.fetchedAt = fetchedAt
        self.top = top
        self.bill = bill
        self.serviceStatus = serviceStatus
        self.monthlyUsage = monthlyUsage
        self.dailyUsage = dailyUsage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fetchedAt = try container.decode(Date.self, forKey: .fetchedAt)
        top = try container.decode(MemberTopResponse.self, forKey: .top)
        bill = try container.decode(BillSummaryResponse.self, forKey: .bill)
        serviceStatus = try container.decode(ServiceStatusResponse.self, forKey: .serviceStatus)
        monthlyUsage = try container.decodeIfPresent([MonthlyUsageService].self, forKey: .monthlyUsage) ?? []
        dailyUsage = try container.decodeIfPresent([DailyUsageService].self, forKey: .dailyUsage) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fetchedAt, forKey: .fetchedAt)
        try container.encode(top, forKey: .top)
        try container.encode(bill, forKey: .bill)
        try container.encode(serviceStatus, forKey: .serviceStatus)
        try container.encode(monthlyUsage, forKey: .monthlyUsage)
        try container.encode(dailyUsage, forKey: .dailyUsage)
    }
}

@main
struct IIJFetcherCLI {
    static func main() async {
        do {
            let options = try parseArguments()
            let client = IIJAPIClient()
            try await client.login(credentials: options.credentials)

            switch options.command {
            case .top:
                let data = try await client.fetchTop()
                try emitJSON(data)
            case .bill:
                let data = try await client.fetchBillSummary()
                try emitJSON(data)
            case .status:
                let data = try await client.fetchServiceStatus()
                try emitJSON(data)
            case .usage:
                let data = try await client.fetchMonthlyUsage()
                try emitJSON(data)
            case .daily:
                let data = try await client.fetchDailyUsage()
                try emitJSON(data)
            case .billDetail:
                let entry = try await resolveBillDetailEntry(options: options, client: client)
                let detail = try await client.fetchBillDetail(entry: entry)
                try emitJSON(detail)
            case .all:
                let top = try await client.fetchTop()
                let bill = try await client.fetchBillSummary()
                let status = try await client.fetchServiceStatus()
                let usage = try await client.fetchMonthlyUsage()
                let daily = try await client.fetchDailyUsage()
                let payload = AggregatePayload(
                    fetchedAt: Date(),
                    top: top,
                    bill: bill,
                    serviceStatus: status,
                    monthlyUsage: usage,
                    dailyUsage: daily
                )
                try emitJSON(payload)
            }
        } catch {
            fputs("Error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func emitJSON<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write("\n".data(using: .utf8)!)
    }

    private static func parseArguments() throws -> CLIOptions {
        var mioId: String?
        var password: String?
        var command: Command = .top
        var billNos: [String] = []
        var billMonth: String?
        var iterator = CommandLine.arguments.dropFirst().makeIterator()

        while let arg = iterator.next() {
            switch arg {
            case "--mio-id":
                mioId = iterator.next()
            case "--password":
                password = iterator.next()
            case "--mode", "--command":
                guard let next = iterator.next(), let cmd = Command(rawValue: next) else {
                    throw CLIError(message: "--mode には \(Command.allCases.map { $0.rawValue }.joined(separator: ", ")) のいずれかを指定してください")
                }
                command = cmd
            case "--bill-no":
                guard let value = iterator.next() else {
                    throw CLIError(message: "--bill-no の後に請求番号を指定してください")
                }
                billNos.append(value)
            case "--month":
                guard let value = iterator.next() else {
                    throw CLIError(message: "--month には YYYYMM 形式の値を指定してください")
                }
                billMonth = value
            case "-h", "--help":
                printUsage()
                exit(0)
            default:
                throw CLIError(message: "不明な引数: \(arg)")
            }
        }

        if mioId == nil {
            mioId = ProcessInfo.processInfo.environment["IIJ_MIO_ID"]
        }
        if password == nil {
            password = ProcessInfo.processInfo.environment["IIJ_PASSWORD"]
        }

        guard let id = mioId, !id.isEmpty else {
            throw CLIError(message: "mioID/メールアドレスを --mio-id か IIJ_MIO_ID で指定してください")
        }
        guard let pass = password, !pass.isEmpty else {
            throw CLIError(message: "パスワードを --password か IIJ_PASSWORD で指定してください")
        }

        if let month = billMonth, month.count != 6 || Int(month) == nil {
            throw CLIError(message: "--month には 202510 のような6桁の年月を指定してください")
        }

        return CLIOptions(
            credentials: Credentials(mioId: id, password: pass),
            command: command,
            billDetailBillNos: billNos,
            billDetailMonth: billMonth
        )
    }

    private static func printUsage() {
        let modes = Command.allCases.map { $0.rawValue }.joined(separator: "|")
        let text = """
        使い方: iijfetcher [--mode <\(modes)>] --mio-id <ID> --password <PASS>
          もしくは IIJ_MIO_ID / IIJ_PASSWORD を環境変数で指定してください。
        デフォルトの --mode は top です。
        bill-detail モードでは --bill-no (複数指定可) か --month YYYYMM で対象の明細を選べます。
        """
        print(text)
    }

    private static func resolveBillDetailEntry(options: CLIOptions, client: IIJAPIClient) async throws -> BillSummaryResponse.BillEntry {
        if !options.billDetailBillNos.isEmpty {
            return BillSummaryResponse.BillEntry(
                billNoList: options.billDetailBillNos,
                month: options.billDetailMonth,
                totalAmount: nil,
                usedPoint: nil,
                isUnpaid: nil
            )
        }

        let summary = try await client.fetchBillSummary()
        if let month = options.billDetailMonth {
            if let entry = summary.billList.first(where: { $0.month == month }) {
                return entry
            }
            throw CLIError(message: "指定した月 \(month) の請求データが見つかりませんでした")
        }

        guard let latest = summary.billList.first else {
            throw CLIError(message: "請求サマリが空です")
        }
        return latest
    }
}

final class IIJAPIClient {
    private let session: URLSession
    private let decoder = JSONDecoder()
    init() {
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = true
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.httpAdditionalHeaders = [
            "Accept": "application/json",
            "User-Agent": "IIJFetcher/1.0"
        ]
        session = URLSession(configuration: config)
    }

    func login(credentials: Credentials) async throws {
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
            throw CLIError(message: "ログインエラー: \(errorCode)")
        }
    }

    func fetchTop(serviceCode: String? = nil) async throws -> MemberTopResponse {
        var payload: [String: String] = [:]
        if let serviceCode {
            payload["serviceCode"] = serviceCode
        }
        let data = try await request(
            path: "/api/member/top",
            method: "POST",
            body: try JSONSerialization.data(withJSONObject: payload, options: [])
        )
        try throwIfAPIError(data)
        return try decoder.decode(MemberTopResponse.self, from: data)
    }

    func fetchBillSummary() async throws -> BillSummaryResponse {
        let data = try await request(path: "/api/member/getBillSummary", method: "GET")
        try throwIfAPIError(data)
        return try decoder.decode(BillSummaryResponse.self, from: data)
    }

    func fetchServiceStatus() async throws -> ServiceStatusResponse {
        let data = try await request(path: "/api/member/getServiceStatus", method: "GET")
        try throwIfAPIError(data)
        return try decoder.decode(ServiceStatusResponse.self, from: data)
    }

    func fetchMonthlyUsage() async throws -> [MonthlyUsageService] {
        let landingData = try await request(path: "/service/setup/hdc/viewmonthlydata/", method: "GET", contentType: nil)
        guard let landingHTML = String(data: landingData, encoding: .utf8) else { return [] }
        let landingParser = DataUsageHTMLParser(html: landingHTML)
        let forms = landingParser.extractLandingPageForms().forms
        guard !forms.isEmpty else { return [] }

        var services: [MonthlyUsageService] = []
        for form in forms {
            guard let body = formURLEncoded([
                "hdoCode": form.hdoCode,
                "_csrf": form.csrfToken
            ]) else { continue }

            let response = try await request(
                path: "/service/setup/hdc/viewmonthlydata/",
                method: "POST",
                body: body,
                contentType: "application/x-www-form-urlencoded"
            )
            guard let detailHTML = String(data: response, encoding: .utf8) else { continue }
            let detailParser = DataUsageHTMLParser(html: detailHTML)
            if let service = detailParser.parseMonthlyService(hdoCode: form.hdoCode) {
                services.append(service)
            }
        }

        return services
    }

    func fetchDailyUsage() async throws -> [DailyUsageService] {
        let landingData = try await request(path: "/service/setup/hdc/viewdailydata/", method: "GET", contentType: nil)
        guard let landingHTML = String(data: landingData, encoding: .utf8) else { return [] }
        let landingParser = DataUsageHTMLParser(html: landingHTML)
        let landing = landingParser.extractLandingPageForms()
        let forms = landing.forms
        let previewServices = landingParser.previewDailyServices(for: forms)
        guard !forms.isEmpty else { return [] }

        var services: [DailyUsageService] = []

        for form in forms {
            guard let detailHTML = try await requestDailyDetailHTML(hdoCode: form.hdoCode, csrfToken: form.csrfToken) else {
                continue
            }

            let detailParser = DataUsageHTMLParser(html: detailHTML)
            guard let baseService = detailParser.parseDailyService(hdoCode: form.hdoCode) else {
                continue
            }

            let merged = mergeDailyServices(primary: baseService, overlay: previewServices[form.hdoCode])
            services.append(merged)
        }

        return services
    }

    func fetchBillDetail(entry: BillSummaryResponse.BillEntry) async throws -> BillDetailResponse {
        let html = try await requestBillDetailHTML(for: entry)
        guard let detail = BillDetailHTMLParser(html: html).parse() else {
            throw CLIError(message: "請求明細の解析に失敗しました")
        }
        return detail
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

    private func requestBillDetailHTML(for entry: BillSummaryResponse.BillEntry) async throws -> String {
        guard let billNos = entry.billNoList, !billNos.isEmpty else {
            throw CLIError(message: "billNoList が空です")
        }
        guard let body = formURLEncodedArray(name: "billNoList", values: billNos) else {
            throw CLIError(message: "リクエストの組み立てに失敗しました")
        }
        let data = try await request(
            path: "/customer/bill/detail/",
            method: "POST",
            body: body,
            contentType: "application/x-www-form-urlencoded"
        )
        guard let html = String(data: data, encoding: .utf8) else {
            throw CLIError(message: "請求明細のHTMLを解釈できませんでした")
        }
        if html.contains("システムエラー") {
            throw CLIError(message: "請求明細ページがエラーを返しました")
        }
        return html
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

    private func request(path: String, method: String, body: Data? = nil, contentType: String? = "application/json") async throws -> Data {
        guard let url = URL(string: "https://www.iijmio.jp\(path)") else {
            throw CLIError(message: "無効なURL: \(path)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        if let body = body {
            request.httpBody = body
            if let contentType {
                request.setValue(contentType, forHTTPHeaderField: "Content-Type")
            }
        }
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CLIError(message: "HTTPレスポンスを取得できませんでした")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw CLIError(message: "HTTPステータス \(httpResponse.statusCode) で失敗しました")
        }
        return data
    }

    private func decodeAPIErrorIfNeeded(from data: Data) throws -> String? {
        guard let envelope = try? decoder.decode(APIErrorEnvelope.self, from: data) else {
            return nil
        }
        return envelope.error
    }

    private func throwIfAPIError(_ data: Data) throws {
        if let errorCode = try decodeAPIErrorIfNeeded(from: data) {
            throw CLIError(message: "APIエラー: \(errorCode)")
        }
    }

    private func formURLEncoded(_ params: [String: String]) -> Data? {
        var components = URLComponents()
        components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let query = components.percentEncodedQuery else { return nil }
        return query.data(using: .utf8)
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
}
