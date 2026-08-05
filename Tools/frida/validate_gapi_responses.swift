import Foundation

enum ValidationError: LocalizedError {
    case usage
    case missingTrafficLine(String)
    case emptyServices
    case emptyBills
    case emptyMonthlyUsage
    case emptyDailyUsage
    case emptyMonthlyEntries
    case emptyDailyEntries
    case emptyMonthlyChartPoints
    case emptyDailyChartPoints
    case invalidRemainingData
    case invalidLoginResponse
    case missingBillDetail

    var errorDescription: String? {
        switch self {
        case .usage:
            return "Usage: validate-gapi lineInfo.json contract.json usageFee.json dataTraffic.json pastDataTraffic.json [...]"
        case .missingTrafficLine(let serviceCode):
            return "pastDataTraffic could not be matched to a traffic line: \(serviceCode)"
        case .emptyServices:
            return "Mapped payload contains no services"
        case .emptyBills:
            return "Mapped payload contains no bills"
        case .emptyMonthlyUsage:
            return "Mapped payload contains no monthly usage"
        case .emptyDailyUsage:
            return "Mapped payload contains no daily usage"
        case .emptyMonthlyEntries:
            return "Mapped monthly usage contains no entries"
        case .emptyDailyEntries:
            return "Mapped daily usage contains no entries"
        case .emptyMonthlyChartPoints:
            return "Mapped monthly usage produces no chart points"
        case .emptyDailyChartPoints:
            return "Mapped daily usage produces no chart points"
        case .invalidRemainingData:
            return "Mapped remaining data is invalid"
        case .invalidLoginResponse:
            return "Login response model validation failed"
        case .missingBillDetail:
            return "usageFee could not be mapped to BillDetailResponse"
        }
    }
}

@main
struct GAPIResponseValidator {
    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count >= 5 else {
            throw ValidationError.usage
        }

        let decoder = JSONDecoder()
        let lineInfo = try decode(GAPILineInfoResponse.self, path: arguments[0], decoder: decoder)
        let contract = try decode(GAPIContractResponse.self, path: arguments[1], decoder: decoder)
        let usageFee = try decode(GAPIUsageFeeResponse.self, path: arguments[2], decoder: decoder)
        let dataTraffic = try decode(GAPIDataTrafficResponse.self, path: arguments[3], decoder: decoder)

        let loginFixture = Data(
            #"{"mioId":"MA0000000","token":"fixture-token","contractorName":"Fixture"}"#.utf8
        )
        let login = try decoder.decode(GAPILoginResponse.self, from: loginFixture)
        guard login.mioId == "MA0000000", login.token == "fixture-token" else {
            throw ValidationError.invalidLoginResponse
        }

        let resolvedLines = dataTraffic.dataTraffic.resolvedLines
        var pastTraffic: [GAPIPastTrafficResult] = []
        for path in arguments.dropFirst(4) {
            let response = try decode(GAPIPastDataTrafficResponse.self, path: path, decoder: decoder)
            let line = resolvedLines.first { candidate in
                guard let responseCode = response.serviceCode else { return false }
                return candidate.serviceCode == responseCode || candidate.lineServiceCode == responseCode
            } ?? resolvedLines.first
            guard let line else {
                throw ValidationError.missingTrafficLine(response.serviceCode ?? "<missing>")
            }
            pastTraffic.append(GAPIPastTrafficResult(line: line, response: response))
        }

        let payload = MyIIJmioPayloadMapper.aggregatePayload(
            lineInfo: lineInfo,
            dataTraffic: dataTraffic,
            contract: contract,
            usageFee: usageFee,
            pastTraffic: pastTraffic
        )

        guard !payload.top.serviceInfoList.isEmpty else { throw ValidationError.emptyServices }
        guard !payload.bill.billList.isEmpty else { throw ValidationError.emptyBills }
        guard !payload.monthlyUsage.isEmpty else { throw ValidationError.emptyMonthlyUsage }
        guard !payload.dailyUsage.isEmpty else { throw ValidationError.emptyDailyUsage }
        guard payload.monthlyUsage.contains(where: { !$0.entries.isEmpty }) else {
            throw ValidationError.emptyMonthlyEntries
        }
        guard payload.dailyUsage.contains(where: { !$0.entries.isEmpty }) else {
            throw ValidationError.emptyDailyEntries
        }
        let monthlyPoints = monthlyChartPoints(from: payload.monthlyUsage)
        let dailyPoints = dailyChartPoints(from: payload.dailyUsage)
        guard !monthlyPoints.isEmpty else { throw ValidationError.emptyMonthlyChartPoints }
        guard !dailyPoints.isEmpty else { throw ValidationError.emptyDailyChartPoints }
        guard payload.top.serviceInfoList.allSatisfy({ service in
            guard let remaining = service.remainingDataGB else { return false }
            return remaining.isFinite && remaining >= 0
        }) else {
            throw ValidationError.invalidRemainingData
        }

        guard let firstBill = payload.bill.billList.first,
              let billDetail = MyIIJmioPayloadMapper.billDetail(entry: firstBill, usageFee: usageFee),
              !billDetail.sections.isEmpty else {
            throw ValidationError.missingBillDetail
        }

        let encoded = try JSONEncoder().encode(payload)
        _ = try JSONDecoder().decode(AggregatePayload.self, from: encoded)

        print(
            "GAPI_MAPPING_OK "
                + "services=\(payload.top.serviceInfoList.count) "
                + "bills=\(payload.bill.billList.count) "
                + "monthlyServices=\(payload.monthlyUsage.count) "
                + "dailyServices=\(payload.dailyUsage.count) "
                + "monthlyPoints=\(monthlyPoints.count) "
                + "dailyPoints=\(dailyPoints.count)"
        )
    }

    private static func decode<Value: Decodable>(
        _ type: Value.Type,
        path: String,
        decoder: JSONDecoder
    ) throws -> Value {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try decoder.decode(type, from: data)
    }
}
