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

struct AggregatePayload: Codable {
    let fetchedAt: Date
    let top: MemberTopResponse
    let bill: BillSummaryResponse
    let serviceStatus: ServiceStatusResponse
}

extension MemberTopResponse.ServiceInfo {
    var displayPlanName: String {
        planName ?? "未設定プラン"
    }

    var phoneLabel: String {
        phoneNo ?? "-"
    }

    var remainingDataGB: Double? {
        let sorted = couponData?.sorted { (lhs, rhs) -> Bool in
            (lhs.sequenceNo ?? 0) < (rhs.sequenceNo ?? 0)
        }
        return sorted?.first { ($0.couponValue ?? 0) > 0 }?.couponValue
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
