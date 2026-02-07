import Foundation

struct Credentials: Codable, Equatable {
    var mioId: String
    var password: String
}

struct MemberTopResponse: Codable {
    struct ServiceInfo: Codable, Identifiable {
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

        var id: String { serviceCode ?? UUID().uuidString }
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
    struct BillEntry: Codable, Identifiable {
        let billNoList: [String]?
        let month: String?
        let totalAmount: Int?
        let usedPoint: Int?
        let isUnpaid: Bool?

        var id: String { (billNoList?.joined(separator: "-")) ?? (month ?? UUID().uuidString) }
    }

    let billList: [BillEntry]
    let isVoiceSim: Bool?
    let isImt: Bool?
}

extension BillSummaryResponse {
    static let empty = BillSummaryResponse(billList: [], isVoiceSim: nil, isImt: nil)
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
    struct ServiceStatus: Codable, Identifiable {
        struct SimInfo: Codable, Identifiable {
            let simType: String?
            let status: String?

            var id: String { (simType ?? "?") + (status ?? "") }
        }

        let simInfoList: [SimInfo]?
        let serviceCodePrefix: String?
        let stopDate: String?
        let planCode: String?
        let isBic: Bool?
        let status: String?

        var id: String { (serviceCodePrefix ?? "?") + (planCode ?? UUID().uuidString) }
    }

    let serviceInfoList: [ServiceStatus]
    let jmbNumberChangePossible: Bool?
}

extension ServiceStatusResponse {
    static let empty = ServiceStatusResponse(serviceInfoList: [], jmbNumberChangePossible: nil)
}

struct AggregatePayload: Codable {
    let fetchedAt: Date
    let top: MemberTopResponse
    let bill: BillSummaryResponse
    let serviceStatus: ServiceStatusResponse
    let monthlyUsage: [MonthlyUsageService]
    let dailyUsage: [DailyUsageService]

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

    private enum CodingKeys: String, CodingKey {
        case fetchedAt
        case top
        case bill
        case serviceStatus
        case monthlyUsage
        case dailyUsage
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

extension MemberTopResponse.ServiceInfo {
    var displayPlanName: String {
        planName ?? "未設定プラン"
    }

    var phoneLabel: String {
        phoneNo ?? "-"
    }

    var remainingDataGB: Double? {
        guard let couponData else {
            return 0
        }
        let sum = couponData.reduce(0.0) { total, entry in
            guard let sequenceNo = entry.sequenceNo, (0...4).contains(sequenceNo) else {
                return total
            }
            return total + max(entry.couponValue ?? 0, 0)
        }
        return max(sum, 0)
    }

    var carryoverRemainingGB: Double {
        guard let couponData else {
            return 0
        }
        let sum = couponData.reduce(0.0) { total, entry in
            guard let sequenceNo = entry.sequenceNo, (1...4).contains(sequenceNo) else {
                return total
            }
            return total + max(entry.couponValue ?? 0, 0)
        }
        return max(sum, 0)
    }
}

extension BillSummaryResponse.BillEntry {
    var formattedMonth: String {
        guard let month else { return "-" }
        let year = month.prefix(4)
        let monthValue = month.suffix(2)
        return "\(year)年\(monthValue)月"
    }

    var formattedAmount: String {
        guard let totalAmount else { return "-" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "¥"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: totalAmount)) ?? "¥\(totalAmount)"
    }
}
