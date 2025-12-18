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
                    amount: "2,980",
                    miowari: "-",
                    month: "202404"
                ),
                hasVouchers: false,
                usagePeriod: "2024/05/01 - 2024/05/31",
                prefixList: ["hdo"]
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
                serviceCode: "hdo0123456",
                totalCapacity: 20,
                dataShareExistence: true,
                planName: "ギガプラン 20GB (音声)",
                chargePlan: "Giga Plan",
                serviceName: "メイン回線",
                phoneNo: "080-1234-5678",
                couponData: [
                    MemberTopResponse.ServiceInfo.CouponEntry(
                        adjustmentCoupon: false,
                        sequenceNo: 1,
                        month: "202405",
                        couponValue: 14.3
                    )
                ]
            )
        ]
    }

    private static func sampleBill() -> BillSummaryResponse {
        BillSummaryResponse(
            billList: [
                BillSummaryResponse.BillEntry(
                    billNoList: ["BILL-MOCK-001"],
                    month: "202404",
                    totalAmount: 2980,
                    usedPoint: 0,
                    isUnpaid: false
                ),
                BillSummaryResponse.BillEntry(
                    billNoList: ["BILL-MOCK-002"],
                    month: "202403",
                    totalAmount: 3100,
                    usedPoint: 200,
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
                            simType: "Voice+Data",
                            status: "開通済み"
                        )
                    ],
                    serviceCodePrefix: "hdo",
                    stopDate: nil,
                    planCode: "giga20",
                    isBic: false,
                    status: "ご利用中"
                )
            ],
            jmbNumberChangePossible: true
        )
    }

    private static func sampleMonthlyUsage() -> [MonthlyUsageService] {
        let entries = [
            MonthlyUsageEntry(
                monthLabel: "2024年05月",
                highText: "5.7GB",
                lowText: "0.2GB",
                note: "ホスピタリティ割引適用",
                hasData: true
            ),
            MonthlyUsageEntry(
                monthLabel: "2024年04月",
                highText: "12.8GB",
                lowText: nil,
                note: nil,
                hasData: true
            ),
            MonthlyUsageEntry(
                monthLabel: "2024年03月",
                highText: "9.4GB",
                lowText: "0.4GB",
                note: nil,
                hasData: true
            ),
            MonthlyUsageEntry(
                monthLabel: "2024年02月",
                highText: "7.2GB",
                lowText: "0.1GB",
                note: nil,
                hasData: true
            ),
            MonthlyUsageEntry(
                monthLabel: "2024年01月",
                highText: "6.9GB",
                lowText: nil,
                note: "5Gエリア利用増",
                hasData: true
            )
        ]

        return [
            MonthlyUsageService(
                hdoCode: "hdo0123456",
                titlePrimary: "メイン回線",
                titleDetail: "ギガプラン 20GB",
                entries: entries
            )
        ]
    }

    private static func sampleDailyUsage() -> [DailyUsageService] {
        let entries = [
            DailyUsageEntry(
                dateLabel: "2024年05月20日",
                highText: "820MB",
                lowText: "120MB",
                note: "テザリング利用",
                hasData: true
            ),
            DailyUsageEntry(
                dateLabel: "2024年05月19日",
                highText: "640MB",
                lowText: nil,
                note: nil,
                hasData: true
            ),
            DailyUsageEntry(
                dateLabel: "2024年05月18日",
                highText: "1.2GB",
                lowText: nil,
                note: "動画視聴",
                hasData: true
            ),
            DailyUsageEntry(
                dateLabel: "2024年05月17日",
                highText: "550MB",
                lowText: "80MB",
                note: nil,
                hasData: true
            ),
            DailyUsageEntry(
                dateLabel: "2024年05月16日",
                highText: "430MB",
                lowText: nil,
                note: nil,
                hasData: true
            )
        ]

        return [
            DailyUsageService(
                hdoCode: "hdo0123456",
                titlePrimary: "メイン回線",
                titleDetail: "ギガプラン 20GB",
                entries: entries
            )
        ]
    }
}
