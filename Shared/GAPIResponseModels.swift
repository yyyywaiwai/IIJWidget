import Foundation

// Wire-format models stay separate from app-facing models and payload mapping.
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
        var seen = Set<String>()
        return (hdcLines + groupedLines).filter { !$0.id.isEmpty && seen.insert($0.id).inserted }
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

    var id: String { lineServiceCode ?? serviceCode ?? "" }
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

private extension KeyedDecodingContainer {
    func decodeLossyStringIfPresent(forKey key: Key) throws -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            // JSON numbers may exceed Int's range. Preserve their text instead of trapping.
            return Int(exactly: value).map(String.init) ?? String(value)
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
