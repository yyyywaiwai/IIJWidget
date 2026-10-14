import Foundation

enum MyIIJmioPayloadMapper {
    static func aggregatePayload(
        lineInfo: GAPILineInfoResponse,
        dataTraffic: GAPIDataTrafficResponse,
        contract: GAPIContractResponse,
        usageFee: GAPIUsageFeeResponse,
        pastTraffic: [GAPIPastTrafficResult],
        now: Date = Date(),
        calendar: Calendar = UsageDateLabel.calendar
    ) -> AggregatePayload {
        let billing = bill(usageFee: usageFee)
        return AggregatePayload(
            fetchedAt: now,
            top: top(dataTraffic: dataTraffic),
            bill: billing,
            serviceStatus: serviceStatus(contract: contract, dataTraffic: dataTraffic),
            monthlyUsage: monthlyUsage(from: pastTraffic, now: now, calendar: calendar),
            dailyUsage: mergeRecentUsage(
                dailyUsage(from: pastTraffic, now: now, calendar: calendar),
                dataTraffic: dataTraffic, now: now, calendar: calendar
            ),
            billDetails: Dictionary(billing.billList.compactMap { entry in
                guard let detail = billDetail(entry: entry, usageFee: usageFee) else { return nil }
                return (entry.id, detail)
            }, uniquingKeysWith: { _, last in last })
        )
    }

    static func top(
        dataTraffic: GAPIDataTrafficResponse
    ) -> TrafficSummary {
        let services = dataTraffic.dataTraffic.resolvedLines.map { resolved in
            let line = resolved.line
            let current = line.thisMonthDataList
            let remaining = amountInGigabytes(current?.availableDataTraffic, unit: current?.availableDataTrafficUnit)
                ?? (line.expireList.isEmpty ? line.couponValue : line.expireList.reduce(0) {
                    $0 + (amountInGigabytes($1.remainingDataTraffic, unit: $1.dataUnit) ?? 0)
                })
            return TrafficSummary.ServiceInfo(
                id: resolved.id,
                serviceCode: resolved.serviceCode,
                groupServiceCode: line.groupServiceCode,
                totalCapacity: amountInGigabytes(current?.maxDataTraffic, unit: current?.maxDataTrafficUnit),
                remainingDataGB: remaining.map { max($0, 0) },
                planName: resolved.planName,
                phoneNo: line.telNo ?? line.msIsdn
            )
        }
        return TrafficSummary(serviceInfoList: services)
    }

    static func bill(usageFee: GAPIUsageFeeResponse) -> BillSummaryResponse {
        let entries = usageFee.billingSummary.map { summary in
            BillSummaryResponse.BillEntry(
                billingNumber: summary.billingNo,
                month: normalizedYearMonth(summary.billingMonth),
                totalAmount: integerAmount(summary.billingTotalAmount),
                isUnpaid: nil
            )
        }
        return BillSummaryResponse(billList: entries)
    }

    static func billDetail(
        entry: BillSummaryResponse.BillEntry,
        usageFee: GAPIUsageFeeResponse
    ) -> BillDetailResponse? {
        let expectedBillNumber = entry.billingNumber
        let expectedMonth = normalizedYearMonth(entry.month)
        guard let summary = usageFee.billingSummary.first(where: { candidate in
            if let number = candidate.billingNo, let expectedBillNumber {
                return number == expectedBillNumber
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
                if let lineServiceCode = trafficLine.lineServiceCode {
                    return contractLine.lineServiceCode == lineServiceCode
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
                id: trafficLine.id,
                simInfoList: [
                    ServiceStatusResponse.ServiceStatus.SimInfo(
                        simType: simType,
                        status: status
                    )
                ],
                serviceCodePrefix: trafficLine.serviceCode.map { String($0.prefix(3)) },
                planCode: matchingContract?.chargePlan ?? trafficLine.parentPlanCode,
                status: status
            )
        }
        return ServiceStatusResponse(serviceInfoList: statuses)
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
                    highSpeedGB: amountInGigabytes(Double(entry.dataTraffic ?? ""), unit: result.response.lastFiveMonthDataUnit),
                    lowSpeedGB: nil,
                    note: nil,
                    hasData: entry.dataTraffic != nil
                )
            }
            return MonthlyUsageService(
                lineID: result.line.id,
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
                    highSpeedMB: amountInGigabytes(Double(entry.dataTraffic ?? ""), unit: entry.dataTrafficUnit ?? "MB").map { $0 * 1024 },
                    lowSpeedMB: nil,
                    note: entry.dayOfWeek,
                    hasData: entry.dataTraffic != nil
                )
            }
            return DailyUsageService(
                lineID: result.line.id,
                titlePrimary: result.line.planName ?? "IIJmio回線",
                titleDetail: result.line.line.telNo ?? result.line.line.msIsdn,
                entries: entries
            )
        }
    }

    static func mergeRecentUsage(
        _ history: [DailyUsageService],
        dataTraffic: GAPIDataTrafficResponse,
        now: Date,
        calendar: Calendar
    ) -> [DailyUsageService] {
        dataTraffic.dataTraffic.resolvedLines.map { line in
            var entries = history.first { $0.lineID == line.id }?.entries ?? []
            if let recent = line.line.lastSevenDaysDataList {
                for day in recent.dailyDataList {
                    guard let month = Int(day.month ?? ""), (1...12).contains(month),
                          let date = Int(day.date ?? ""), (1...31).contains(date) else { continue }
                    let label = String(format: "%04d年%02d月%02d日",
                                       resolvedYear(forMonth: month, now: now, calendar: calendar), month, date)
                    let entry = DailyUsageEntry(
                        dateLabel: label,
                        highSpeedMB: amountInGigabytes(Double(day.high ?? ""), unit: recent.lastSevenDaysDataHighUnit ?? "MB").map { $0 * 1024 },
                        lowSpeedMB: amountInGigabytes(Double(day.low ?? ""), unit: recent.lastSevenDaysDataLowUnit ?? "MB").map { $0 * 1024 },
                        note: day.dayOfWeek,
                        hasData: day.high != nil || day.low != nil
                    )
                    if entry.hasData {
                        entries.removeAll { $0.dateLabel == label }
                        entries.append(entry)
                    }
                }
            }
            return DailyUsageService(lineID: line.id, titlePrimary: line.planName ?? "IIJmio回線",
                                     titleDetail: line.line.telNo ?? line.line.msIsdn,
                                     entries: entries.sorted { $0.dateLabel > $1.dateLabel })
        }
    }

    private static func amountInGigabytes(_ value: Double?, unit: String?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        let normalized = unit?.uppercased() ?? "GB"
        if normalized.contains("TB") { return value * 1024 }
        if normalized.contains("MB") { return value / 1024 }
        if normalized.contains("KB") { return value / (1024 * 1024) }
        return value
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

    nonisolated private static func currencyText(_ value: Double) -> String {
        let formatted: String
        if let integer = Int(exactly: value) {
            formatted = String(integer)
        } else {
            formatted = String(format: "%.2f", value)
                .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
        }
        return "\(formatted)円"
    }
}
