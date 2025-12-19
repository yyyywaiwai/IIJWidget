import Foundation

enum MockPayloadProvider {
    static let credentials = Credentials(
        mioId: "iiyokoiyo@yajyusenp.ai",
        password: "810"
    )

    static func isMockCredentials(_ credentials: Credentials) -> Bool {
        credentials.mioId.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(self.credentials.mioId) == .orderedSame
            && credentials.password.trimmingCharacters(in: .whitespacesAndNewlines) == self.credentials.password
    }

    static func aggregatePayload() -> AggregatePayload {
        let services = sampleServices()
        let bill = sampleBill()
        let status = sampleServiceStatus()
        let monthly = sampleMonthlyUsage()
        let daily = sampleDailyUsage()

        return AggregatePayload(
            fetchedAt: Date(),
            top: MemberTopResponse(
                serviceInfoList: services,
                billSummary: MemberTopResponse.BillSummary(
                    amount: nil,
                    miowari: nil,
                    month: nil
                ),
                hasVouchers: false,
                usagePeriod: "10ヵ月",
                prefixList: ["hdc", "hdu"]
            ),
            bill: bill,
            serviceStatus: status,
            monthlyUsage: monthly,
            dailyUsage: daily
        )
    }

    // MARK: - Private helpers

    private static func sampleServices() -> [MemberTopResponse.ServiceInfo] {
        [
            MemberTopResponse.ServiceInfo(
                dataShareNotCovered: false,
                serviceCode: "hdc92847349",
                totalCapacity: 10,
                dataShareExistence: false,
                planName: "ギガプラン",
                chargePlan: "10",
                serviceName: "音声SIM",
                phoneNo: "070-5283-7491",
                couponData: [
                    MemberTopResponse.ServiceInfo.CouponEntry(
                        adjustmentCoupon: false,
                        sequenceNo: 0,
                        month: "202512",
                        couponValue: 0
                    ),
                    MemberTopResponse.ServiceInfo.CouponEntry(
                        adjustmentCoupon: nil,
                        sequenceNo: 1,
                        month: "202601",
                        couponValue: 1.8
                    ),
                    MemberTopResponse.ServiceInfo.CouponEntry(
                        adjustmentCoupon: nil,
                        sequenceNo: 2,
                        month: "202602",
                        couponValue: 0
                    ),
                    MemberTopResponse.ServiceInfo.CouponEntry(
                        adjustmentCoupon: nil,
                        sequenceNo: 3,
                        month: "202603",
                        couponValue: 0
                    )
                ]
            )
        ]
    }

    private static func sampleBill() -> BillSummaryResponse {
        BillSummaryResponse(
            billList: [
                BillSummaryResponse.BillEntry(
                    billNoList: ["111015580113"],
                    month: "202511",
                    totalAmount: 1404,
                    usedPoint: 0,
                    isUnpaid: false
                ),
                BillSummaryResponse.BillEntry(
                    billNoList: ["111005999429"],
                    month: "202510",
                    totalAmount: 1404,
                    usedPoint: 0,
                    isUnpaid: false
                ),
                BillSummaryResponse.BillEntry(
                    billNoList: ["110996481070"],
                    month: "202509",
                    totalAmount: 904,
                    usedPoint: 0,
                    isUnpaid: false
                ),
                BillSummaryResponse.BillEntry(
                    billNoList: ["110987036127"],
                    month: "202508",
                    totalAmount: 904,
                    usedPoint: 0,
                    isUnpaid: false
                ),
                BillSummaryResponse.BillEntry(
                    billNoList: ["110977637436"],
                    month: "202507",
                    totalAmount: 904,
                    usedPoint: 0,
                    isUnpaid: false
                ),
                BillSummaryResponse.BillEntry(
                    billNoList: ["110968293003"],
                    month: "202506",
                    totalAmount: 903,
                    usedPoint: 0,
                    isUnpaid: false
                ),
                BillSummaryResponse.BillEntry(
                    billNoList: ["110959041819"],
                    month: "202505",
                    totalAmount: 903,
                    usedPoint: 0,
                    isUnpaid: false
                ),
                BillSummaryResponse.BillEntry(
                    billNoList: ["110949886453"],
                    month: "202504",
                    totalAmount: 1349,
                    usedPoint: 0,
                    isUnpaid: false
                ),
                BillSummaryResponse.BillEntry(
                    billNoList: ["110939799284", "110940851950"],
                    month: "202503",
                    totalAmount: 4353,
                    usedPoint: 0,
                    isUnpaid: false
                )
            ],
            isVoiceSim: true,
            isImt: false
        )
    }

    private static func sampleServiceStatus() -> ServiceStatusResponse {
        ServiceStatusResponse(
            serviceInfoList: [
                ServiceStatusResponse.ServiceStatus(
                    simInfoList: [
                        ServiceStatusResponse.ServiceStatus.SimInfo(
                            simType: "2",
                            status: "O"
                        )
                    ],
                    serviceCodePrefix: "hdc",
                    stopDate: "",
                    planCode: "CN1000",
                    isBic: false,
                    status: "O"
                )
            ],
            jmbNumberChangePossible: false
        )
    }

    private static func sampleMonthlyUsage() -> [MonthlyUsageService] {
        let entries = [
            MonthlyUsageEntry(
                monthLabel: "2025年12月",
                highText: "7.71GB",
                lowText: "0.01GB",
                note: nil,
                hasData: true
            ),
            MonthlyUsageEntry(
                monthLabel: "2025年11月",
                highText: "10.58GB",
                lowText: "0.07GB",
                note: nil,
                hasData: true
            ),
            MonthlyUsageEntry(
                monthLabel: "2025年10月",
                highText: "27.86GB",
                lowText: "0.0GB",
                note: nil,
                hasData: true
            ),
            MonthlyUsageEntry(
                monthLabel: "2025年09月",
                highText: "20.2GB",
                lowText: "0.0GB",
                note: nil,
                hasData: true
            ),
            MonthlyUsageEntry(
                monthLabel: "2025年08月",
                highText: "12.03GB",
                lowText: "0.0GB",
                note: nil,
                hasData: true
            ),
            MonthlyUsageEntry(
                monthLabel: "2025年07月",
                highText: "16.04GB",
                lowText: "0.0GB",
                note: nil,
                hasData: true
            ),
            MonthlyUsageEntry(
                monthLabel: "2025年06月",
                highText: "11.51GB",
                lowText: "0.0GB",
                note: nil,
                hasData: true
            ),
            MonthlyUsageEntry(
                monthLabel: "2025年05月",
                highText: "19.45GB",
                lowText: "0.0GB",
                note: nil,
                hasData: true
            ),
            MonthlyUsageEntry(
                monthLabel: "2025年04月",
                highText: "8.81GB",
                lowText: "0.01GB",
                note: nil,
                hasData: true
            ),
            MonthlyUsageEntry(
                monthLabel: "2025年03月",
                highText: "6.04GB",
                lowText: "0.18GB",
                note: nil,
                hasData: true
            ),
            MonthlyUsageEntry(
                monthLabel: "2025年02月",
                highText: nil,
                lowText: nil,
                note: "データ利用はありません",
                hasData: false
            ),
            MonthlyUsageEntry(
                monthLabel: "2025年01月",
                highText: nil,
                lowText: nil,
                note: "データ利用はありません",
                hasData: false
            )
        ]

        return [
            MonthlyUsageService(
                hdoCode: "hdu92847356",
                titlePrimary: "070-5283-7491",
                titleDetail: "（音声・タイプA） / hdc92847349 （ / 10ギガプラン） / 8981300012345678901",
                entries: entries
            )
        ]
    }

    private static func sampleDailyUsage() -> [DailyUsageService] {
        let entries = [
            DailyUsageEntry(dateLabel: "2025年12月19日", highText: "674MB", lowText: nil, note: nil, hasData: true),
            DailyUsageEntry(dateLabel: "2025年12月18日", highText: "0MB", lowText: "0MB", note: nil, hasData: true),
            DailyUsageEntry(dateLabel: "2025年12月17日", highText: "143MB", lowText: "0MB", note: nil, hasData: true),
            DailyUsageEntry(dateLabel: "2025年12月16日", highText: "399MB", lowText: "0MB", note: nil, hasData: true),
            DailyUsageEntry(dateLabel: "2025年12月15日", highText: "277MB", lowText: "0MB", note: nil, hasData: true),
            DailyUsageEntry(dateLabel: "2025年12月14日", highText: "645MB", lowText: "0MB", note: nil, hasData: true),
            DailyUsageEntry(dateLabel: "2025年12月13日", highText: "164MB", lowText: "0MB", note: nil, hasData: true),
            DailyUsageEntry(dateLabel: "2025年12月12日", highText: "462MB", lowText: "0MB", note: nil, hasData: true),
            DailyUsageEntry(dateLabel: "2025年12月11日", highText: "305MB", lowText: "0MB", note: nil, hasData: true),
            DailyUsageEntry(dateLabel: "2025年12月10日", highText: "486MB", lowText: "0MB", note: nil, hasData: true),
            DailyUsageEntry(dateLabel: "2025年12月09日", highText: "1132MB", lowText: "0MB", note: nil, hasData: true),
            DailyUsageEntry(dateLabel: "2025年12月08日", highText: "237MB", lowText: "0MB", note: nil, hasData: true),
            DailyUsageEntry(dateLabel: "2025年12月07日", highText: "319MB", lowText: "0MB", note: nil, hasData: true),
            DailyUsageEntry(dateLabel: "2025年12月06日", highText: "125MB", lowText: "0MB", note: nil, hasData: true),
            DailyUsageEntry(dateLabel: "2025年12月05日", highText: "410MB", lowText: "0MB", note: nil, hasData: true),
            DailyUsageEntry(dateLabel: "2025年12月04日", highText: "389MB", lowText: "0MB", note: nil, hasData: true),
            DailyUsageEntry(dateLabel: "2025年12月03日", highText: "1130MB", lowText: "0MB", note: nil, hasData: true),
            DailyUsageEntry(dateLabel: "2025年12月02日", highText: "610MB", lowText: "0MB", note: nil, hasData: true),
            DailyUsageEntry(dateLabel: "2025年12月01日", highText: "292MB", lowText: "1MB", note: nil, hasData: true),
            DailyUsageEntry(dateLabel: "2025年11月30日", highText: "0MB", lowText: "36MB", note: nil, hasData: true),
            DailyUsageEntry(dateLabel: "2025年11月29日", highText: "0MB", lowText: "22MB", note: nil, hasData: true),
            DailyUsageEntry(dateLabel: "2025年11月28日", highText: "0MB", lowText: "0MB", note: nil, hasData: true),
            DailyUsageEntry(dateLabel: "2025年11月27日", highText: "0MB", lowText: "0MB", note: nil, hasData: true),
            DailyUsageEntry(dateLabel: "2025年11月26日", highText: "282MB", lowText: "6MB", note: nil, hasData: true),
            DailyUsageEntry(dateLabel: "2025年11月25日", highText: "371MB", lowText: "0MB", note: nil, hasData: true),
            DailyUsageEntry(dateLabel: "2025年11月24日", highText: "77MB", lowText: "0MB", note: nil, hasData: true),
            DailyUsageEntry(dateLabel: "2025年11月23日", highText: "78MB", lowText: "0MB", note: nil, hasData: true),
            DailyUsageEntry(dateLabel: "2025年11月22日", highText: "228MB", lowText: "0MB", note: nil, hasData: true),
            DailyUsageEntry(dateLabel: "2025年11月21日", highText: "195MB", lowText: "0MB", note: nil, hasData: true),
            DailyUsageEntry(dateLabel: "2025年11月20日", highText: "455MB", lowText: "0MB", note: nil, hasData: true),
            DailyUsageEntry(dateLabel: "2025年11月19日", highText: "663MB", lowText: "0MB", note: nil, hasData: true)
        ]

        return [
            DailyUsageService(
                hdoCode: "hdu92847356",
                titlePrimary: "070-5283-7491",
                titleDetail: "（音声・タイプA） / hdc92847349（10ギガプラン）8981300012345678901",
                entries: entries
            )
        ]
    }

    static func billDetail(for entry: BillSummaryResponse.BillEntry) -> BillDetailResponse? {
        guard let month = entry.month, let totalAmount = entry.totalAmount else {
            return nil
        }

        let year = String(month.prefix(4))
        let monthValue = String(month.suffix(2))
        let monthText = "\(year)年\(monthValue)月分"

        // 基本料金の計算（合計から通話料とユニバーサル料を引いたもの）
        let universalFee = 3
        let callFee: Int
        let basicFee: Int

        // 請求額に応じて通話料を調整
        switch totalAmount {
        case ..<1000:
            callFee = 0
            basicFee = totalAmount - universalFee
        case 1000..<2000:
            callFee = Int.random(in: 50...200)
            basicFee = totalAmount - callFee - universalFee
        default:
            callFee = Int.random(in: 100...500)
            basicFee = totalAmount - callFee - universalFee
        }

        let basicSection = BillDetailResponse.Section(
            title: "基本料金",
            items: [
                BillDetailResponse.Item(
                    title: "ギガプラン（音声通話機能付き）",
                    detail: "10GBプラン",
                    quantityText: "1",
                    unitPriceText: "¥\(basicFee)",
                    amountText: "¥\(basicFee)"
                )
            ],
            subtotalText: "¥\(basicFee)"
        )

        var sections: [BillDetailResponse.Section] = [basicSection]

        if callFee > 0 {
            let callSection = BillDetailResponse.Section(
                title: "通話・通信料",
                items: [
                    BillDetailResponse.Item(
                        title: "国内音声通話料",
                        detail: "携帯電話宛",
                        quantityText: "\(callFee / 11)秒",
                        unitPriceText: "¥11/30秒",
                        amountText: "¥\(callFee)"
                    )
                ],
                subtotalText: "¥\(callFee)"
            )
            sections.append(callSection)
        }

        let otherSection = BillDetailResponse.Section(
            title: "その他の料金",
            items: [
                BillDetailResponse.Item(
                    title: "ユニバーサルサービス料",
                    detail: nil,
                    quantityText: "1",
                    unitPriceText: "¥\(universalFee)",
                    amountText: "¥\(universalFee)"
                )
            ],
            subtotalText: "¥\(universalFee)"
        )
        sections.append(otherSection)

        // 税込みの金額から税抜きを逆算（簡略化のため総額の約90%とする）
        let subtotal = Int(Double(totalAmount) / 1.1)
        let tax = totalAmount - subtotal

        let taxBreakdowns = [
            BillDetailResponse.TaxBreakdown(
                label: "10%対象",
                amountText: "¥\(subtotal)",
                taxLabel: "消費税等（10%）",
                taxAmountText: "¥\(tax)"
            )
        ]

        return BillDetailResponse(
            monthText: monthText,
            totalAmountText: "¥\(totalAmount.formatted())",
            totalAmount: totalAmount,
            taxBreakdowns: taxBreakdowns,
            sections: sections
        )
    }
}
