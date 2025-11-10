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
}

struct CLIOptions {
    let credentials: Credentials
    let command: Command
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
            case .all:
                let top = try await client.fetchTop()
                let bill = try await client.fetchBillSummary()
                let status = try await client.fetchServiceStatus()
                let payload = AggregatePayload(
                    fetchedAt: Date(),
                    top: top,
                    bill: bill,
                    serviceStatus: status
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

        return CLIOptions(credentials: Credentials(mioId: id, password: pass), command: command)
    }

    private static func printUsage() {
        let modes = Command.allCases.map { $0.rawValue }.joined(separator: "|")
        let text = """
        使い方: iijfetcher [--mode <\(modes)>] --mio-id <ID> --password <PASS>
          もしくは IIJ_MIO_ID / IIJ_PASSWORD を環境変数で指定してください。
        デフォルトの --mode は top です。
        """
        print(text)
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

    private func request(path: String, method: String, body: Data? = nil) async throws -> Data {
        guard let url = URL(string: "https://www.iijmio.jp\(path)") else {
            throw CLIError(message: "無効なURL: \(path)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        if let body = body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
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
}
