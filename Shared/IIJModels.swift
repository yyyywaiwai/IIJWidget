import Foundation

struct Credentials: Codable, Equatable {
    var mioId: String
    var password: String
}

/// GAPIの回線IDと数値を正本にする。会員サイトのクーポン連番は使用しない。
struct TrafficSummary: Codable {
    struct ServiceInfo: Codable, Identifiable {
        let id: String
        let serviceCode: String?
        let groupServiceCode: String?
        let totalCapacity: Double?
        let remainingDataGB: Double?
        let planName: String?
        let phoneNo: String?

        var displayPlanName: String { planName ?? "未設定プラン" }
        var phoneLabel: String { phoneNo ?? "-" }
    }

    let serviceInfoList: [ServiceInfo]
}

struct BillSummaryResponse: Codable {
    struct BillEntry: Codable, Identifiable {
        let billingNumber: String?
        let month: String?
        let totalAmount: Int?
        let isUnpaid: Bool?

        var id: String { billingNumber ?? month ?? "unknown" }
    }

    let billList: [BillEntry]
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

        let id: String
        let simInfoList: [SimInfo]?
        let serviceCodePrefix: String?
        let planCode: String?
        let status: String?
    }

    let serviceInfoList: [ServiceStatus]
}

struct AggregatePayload: Codable {
    let fetchedAt: Date
    let historyFetchedAt: Date
    let top: TrafficSummary
    let bill: BillSummaryResponse
    let serviceStatus: ServiceStatusResponse
    let monthlyUsage: [MonthlyUsageService]
    let dailyUsage: [DailyUsageService]
    var thirtyDayUsage: [DailyUsageService]?
    let billDetails: [String: BillDetailResponse]

    var dailyUsageWithHistory: [DailyUsageService] {
        DailyUsageMerger.merge(history: thirtyDayUsage ?? [], current: dailyUsage)
    }

    init(
        fetchedAt: Date,
        top: TrafficSummary,
        bill: BillSummaryResponse,
        serviceStatus: ServiceStatusResponse,
        monthlyUsage: [MonthlyUsageService],
        dailyUsage: [DailyUsageService],
        billDetails: [String: BillDetailResponse] = [:],
        historyFetchedAt: Date? = nil,
        thirtyDayUsage: [DailyUsageService]? = nil
    ) {
        self.historyFetchedAt = historyFetchedAt ?? fetchedAt
        self.fetchedAt = fetchedAt
        self.top = top
        self.bill = bill
        self.serviceStatus = serviceStatus
        self.monthlyUsage = monthlyUsage
        self.billDetails = billDetails
        self.dailyUsage = dailyUsage
        self.thirtyDayUsage = thirtyDayUsage
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

enum WidgetRefreshError: LocalizedError {
    case missingCredentials
    case unmatchedThirtyDayLine

    var errorDescription: String? {
        switch self {
        case .missingCredentials: return "キーチェーンまたは入力済みの資格情報が見つかりませんでした"
        case .unmatchedThirtyDayLine: return "30日表とGAPIの回線を一意に照合できませんでした"
        }
    }
}
