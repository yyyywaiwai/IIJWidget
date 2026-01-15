import Foundation

enum WidgetRefreshError: LocalizedError {
    case missingCredentials

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "キーチェーンまたは入力済みの資格情報が見つかりませんでした"
        }
    }
}

struct WidgetRefreshService {
    enum LoginSource {
        case sessionCookie
        case keychain
        case manual
        case mock
    }

    enum FetchScope {
        case full
        case topOnly
    }

    struct RefreshOutcome {
        let payload: AggregatePayload
        let loginSource: LoginSource
    }

    private let credentialStore = CredentialStore()
    private let apiClient = IIJAPIClient()
    private let widgetDataStore = WidgetDataStore()
    private let payloadStore = AggregatePayloadStore()
    private let debugStore = DebugResponseStore.shared
    func refreshForWidget(calculateTodayFromRemaining: Bool) async throws -> RefreshOutcome {
        let cached = payloadStore.load()
        let isCompletePayload = {
            guard let cached else { return false }
            return !cached.dailyUsage.isEmpty && !cached.monthlyUsage.isEmpty && !cached.top.serviceInfoList.isEmpty
        }()

        if calculateTodayFromRemaining {
            let scope: FetchScope = isCompletePayload ? .topOnly : .full
            return try await refresh(
                manualCredentials: nil,
                persistManualCredentials: false,
                allowSessionReuse: true,
                allowKeychainFallback: true,
                fetchScope: scope,
                calculateTodayFromRemaining: true,
                dailyFetchMode: .tableOnly
            )
        }

        // トグルOFF時は常にフルフェッチでプレビュー+30日マージ
        return try await refresh(
            manualCredentials: nil,
            persistManualCredentials: false,
            allowSessionReuse: true,
            allowKeychainFallback: true,
            fetchScope: .full,
            calculateTodayFromRemaining: false,
            dailyFetchMode: .mergedPreviewAndTable
        )
    }

    func refresh(
        manualCredentials: Credentials? = nil,
        persistManualCredentials: Bool = true,
        allowSessionReuse: Bool = true,
        allowKeychainFallback: Bool = true,
        fetchScope: FetchScope = .full,
        calculateTodayFromRemaining: Bool = false,
        dailyFetchMode: DailyFetchMode? = nil
    ) async throws -> RefreshOutcome {
        debugStore.beginCaptureSession()
        defer { debugStore.finalizeCaptureSession() }

        let fallbackPayload = payloadStore.load()

        if let mock = mockOutcome(
            manualCredentials: manualCredentials,
            persistManualCredentials: persistManualCredentials,
            allowKeychainFallback: allowKeychainFallback
        ) {
            return mock
        }

        if !allowSessionReuse {
            apiClient.clearPersistedSession()
        }

        let resolvedDailyMode: DailyFetchMode = dailyFetchMode
            ?? (calculateTodayFromRemaining ? .tableOnly : .mergedPreviewAndTable)

        if allowSessionReuse {
            do {
                return finalize(
                    payload: try await fetchUsingExistingSession(scope: fetchScope, fallback: fallbackPayload, dailyFetchMode: resolvedDailyMode, calculateTodayFromRemaining: calculateTodayFromRemaining),
                    source: .sessionCookie
                )
            } catch IIJAPIClientError.invalidSession {
                // セッションが切れているので次の段階へフォールバック
            }
        }

        if allowKeychainFallback, let stored = try credentialStore.load() {
            do {
                return finalize(
                    payload: try await fetchWithCredentials(stored, scope: fetchScope, fallback: fallbackPayload, dailyFetchMode: resolvedDailyMode, calculateTodayFromRemaining: calculateTodayFromRemaining),
                    source: .keychain
                )
            } catch {
                if apiClient.isAuthenticationError(error) {
                    try? credentialStore.delete()
                } else {
                    throw error
                }
            }
        }

        if let manual = manualCredentials, !manual.mioId.isEmpty, !manual.password.isEmpty {
            let payload = try await fetchWithCredentials(manual, scope: fetchScope, fallback: fallbackPayload, dailyFetchMode: resolvedDailyMode, calculateTodayFromRemaining: calculateTodayFromRemaining)
            if persistManualCredentials {
                try? credentialStore.save(manual)
            }
            return finalize(payload: payload, source: .manual)
        }

        throw WidgetRefreshError.missingCredentials
    }

    private func finalize(payload: AggregatePayload, source: LoginSource) -> RefreshOutcome {
        payloadStore.save(payload: payload)
        let previousSnapshot = widgetDataStore.loadSnapshot()
        if var snapshot = WidgetSnapshot(payload: payload, fallback: previousSnapshot) {
            if previousSnapshot?.isRefreshing == true {
                snapshot = snapshot.updatingRefreshingState(true)
            }
            snapshot = snapshot.updatingSuccessUntil(Date().addingTimeInterval(3))
            widgetDataStore.save(snapshot: snapshot)
        }
        if let formattedPayload = DebugPrettyFormatter.prettyJSONString(payload) {
            debugStore.appendResponse(
                title: "AggregatePayload",
                path: "payload",
                category: .api,
                rawText: formattedPayload,
                formattedText: formattedPayload
            )
        }
        return RefreshOutcome(payload: payload, loginSource: source)
    }

    private func mockOutcome(
        manualCredentials: Credentials?,
        persistManualCredentials: Bool,
        allowKeychainFallback: Bool
    ) -> RefreshOutcome? {
        if let manualCredentials, MockPayloadProvider.isMockCredentials(manualCredentials) {
            if persistManualCredentials {
                try? credentialStore.save(manualCredentials)
            }
            return finalize(payload: MockPayloadProvider.aggregatePayload(), source: .mock)
        }

        if allowKeychainFallback,
           let stored = try? credentialStore.load(),
           MockPayloadProvider.isMockCredentials(stored) {
            return finalize(payload: MockPayloadProvider.aggregatePayload(), source: .mock)
        }

        return nil
    }

    func fetchBillDetail(entry: BillSummaryResponse.BillEntry, manualCredentials: Credentials? = nil) async throws -> BillDetailResponse {
        // Check for mock credentials first
        if let manual = manualCredentials, MockPayloadProvider.isMockCredentials(manual) {
            guard let mockDetail = MockPayloadProvider.billDetail(for: entry) else {
                throw NSError(
                    domain: "WidgetRefreshService",
                    code: 0,
                    userInfo: [NSLocalizedDescriptionKey: "モック請求詳細データを生成できませんでした"]
                )
            }
            return mockDetail
        }

        if let stored = try? credentialStore.load(), MockPayloadProvider.isMockCredentials(stored) {
            guard let mockDetail = MockPayloadProvider.billDetail(for: entry) else {
                throw NSError(
                    domain: "WidgetRefreshService",
                    code: 0,
                    userInfo: [NSLocalizedDescriptionKey: "モック請求詳細データを生成できませんでした"]
                )
            }
            return mockDetail
        }

        do {
            return try await apiClient.fetchBillDetail(entry: entry)
        } catch {
            guard apiClient.isAuthenticationError(error) else { throw error }
        }

        if let stored = try? credentialStore.load() {
            do {
                return try await apiClient.fetchBillDetail(entry: entry, credentials: stored)
            } catch {
                if apiClient.isAuthenticationError(error) {
                    try? credentialStore.delete()
                } else {
                    throw error
                }
            }
        }

        if let manual = manualCredentials {
            return try await apiClient.fetchBillDetail(entry: entry, credentials: manual)
        }

        throw WidgetRefreshError.missingCredentials
    }

    func clearSessionArtifacts() {
        apiClient.clearPersistedSession()
        payloadStore.clear()
        widgetDataStore.clear()
    }

    private func fetchUsingExistingSession(
        scope: FetchScope,
        fallback: AggregatePayload?,
        dailyFetchMode: DailyFetchMode,
        calculateTodayFromRemaining: Bool
    ) async throws -> AggregatePayload {
        switch scope {
        case .full:
            let payload = try await apiClient.fetchUsingExistingSession(dailyFetchMode: dailyFetchMode)
            return calculateTodayFromRemaining ? adjustTodayUsage(in: payload) : payload
        case .topOnly:
            let top = try await apiClient.fetchTopUsingExistingSession()
            let payload = buildTopOnlyPayload(top: top, fallback: fallback)
            return calculateTodayFromRemaining ? adjustTodayUsage(in: payload) : payload
        }
    }

    private func fetchWithCredentials(
        _ credentials: Credentials,
        scope: FetchScope,
        fallback: AggregatePayload?,
        dailyFetchMode: DailyFetchMode,
        calculateTodayFromRemaining: Bool
    ) async throws -> AggregatePayload {
        switch scope {
        case .full:
            let payload = try await apiClient.fetchAll(credentials: credentials, dailyFetchMode: dailyFetchMode)
            return calculateTodayFromRemaining ? adjustTodayUsage(in: payload) : payload
        case .topOnly:
            let top = try await apiClient.fetchTopOnly(credentials: credentials)
            let payload = buildTopOnlyPayload(top: top, fallback: fallback)
            return calculateTodayFromRemaining ? adjustTodayUsage(in: payload) : payload
        }
    }

    private func buildTopOnlyPayload(top: MemberTopResponse, fallback: AggregatePayload?) -> AggregatePayload {
        AggregatePayload(
            fetchedAt: Date(),
            top: top,
            bill: fallback?.bill ?? BillSummaryResponse(billList: [], isVoiceSim: nil, isImt: nil),
            serviceStatus: fallback?.serviceStatus ?? ServiceStatusResponse(serviceInfoList: [], jmbNumberChangePossible: nil),
            monthlyUsage: fallback?.monthlyUsage ?? [],
            dailyUsage: fallback?.dailyUsage ?? []
        )
    }

    private func adjustTodayUsage(in payload: AggregatePayload) -> AggregatePayload {
        guard let primaryServiceInfo = payload.top.serviceInfoList.first,
              !payload.dailyUsage.isEmpty else {
            return payload
        }

        let calendar = Calendar.current
        let couponMetrics = resolveCouponMetrics(for: primaryServiceInfo, calendar: calendar)
        let remaining = couponMetrics.remaining

        let totalCapacityBase = resolveTotalCapacity(primary: primaryServiceInfo, services: payload.top.serviceInfoList)
        guard totalCapacityBase > 0 else { return payload }
        let totalCapacityWithCarryover = totalCapacityBase + couponMetrics.carryover

        let today = calendar.startOfDay(for: Date())
        func isTodayEntry(_ label: String) -> Bool {
            if isSameDay(label: label, reference: today, calendar: calendar) {
                return true
            }
            let normalized = label.replacingOccurrences(of: " ", with: "")
            return normalized.contains("当日") || normalized.contains("本日") || normalized.contains("今日")
        }

        let hasConcreteToday = payload.dailyUsage.contains { service in
            service.entries.contains { entry in
                entry.hasData && isTodayEntry(entry.dateLabel)
            }
        }
        if hasConcreteToday {
            return payload
        }

        // 当月の累計MB (当日を除く) を集計
        let currentMonth = calendar.component(.month, from: today)
        let currentYear = calendar.component(.year, from: today)
        let pastMB = payload.dailyUsage.reduce(0.0) { serviceSum, service in
            serviceSum + service.entries.reduce(0.0) { entrySum, entry in
                guard entry.hasData,
                      !isTodayEntry(entry.dateLabel),
                      let entryDate = parsedDate(from: entry.dateLabel, calendar: calendar),
                      calendar.component(.month, from: entryDate) == currentMonth,
                      calendar.component(.year, from: entryDate) == currentYear,
                      !calendar.isDate(entryDate, inSameDayAs: today) else {
                    return entrySum
                }
                return entrySum + (entry.highSpeedMB ?? 0)
            }
        }

        // 残量差分から当日利用量を算出 (GB→MBは1024換算)
        let usedTotalMBFromRemaining = max((totalCapacityWithCarryover - remaining) * 1024, 0)
        let todayMBFromRemaining = max(usedTotalMBFromRemaining - pastMB, 0)
        let monthlyHighSpeedMB = resolveMonthlyHighSpeedMB(
            from: payload,
            year: currentYear,
            month: currentMonth,
            calendar: calendar
        )
        let todayMBFromMonthly = max(monthlyHighSpeedMB - pastMB, 0)
        let todayMB = max(todayMBFromRemaining, todayMBFromMonthly)

        // 当日行をプライマリサービスに追加
        var services = payload.dailyUsage.map { service in
            let filteredEntries = service.entries.filter { !isTodayEntry($0.dateLabel) }
            return DailyUsageService(
                hdoCode: service.hdoCode,
                titlePrimary: service.titlePrimary,
                titleDetail: service.titleDetail,
                entries: filteredEntries
            )
        }
        guard var primaryDaily = services.first else { return payload }
        var filtered = primaryDaily.entries

        let dateFormatter = DateFormatter()
        dateFormatter.calendar = calendar
        dateFormatter.locale = .current
        // 30日データのラベルに合わせて和暦風の年月日表記に統一する
        dateFormatter.dateFormat = "yyyy年MM月dd日"
        let todayLabel = dateFormatter.string(from: today)

        let todayEntry = DailyUsageEntry(
            dateLabel: todayLabel,
            highText: String(format: "%.0fMB", todayMB),
            lowText: nil,
            note: nil,
            hasData: true
        )
        filtered.append(todayEntry)

        // 新しいエントリを日付降順で並べる
        filtered.sort { lhs, rhs in
            guard let lhsDate = parsedDate(from: lhs.dateLabel, calendar: calendar),
                  let rhsDate = parsedDate(from: rhs.dateLabel, calendar: calendar) else {
                return lhs.dateLabel > rhs.dateLabel
            }
            return lhsDate > rhsDate
        }

        primaryDaily = DailyUsageService(
            hdoCode: primaryDaily.hdoCode,
            titlePrimary: primaryDaily.titlePrimary,
            titleDetail: primaryDaily.titleDetail,
            entries: filtered
        )
        services[0] = primaryDaily

        return AggregatePayload(
            fetchedAt: payload.fetchedAt,
            top: payload.top,
            bill: payload.bill,
            serviceStatus: payload.serviceStatus,
            monthlyUsage: payload.monthlyUsage,
            dailyUsage: services
        )
    }

    private func isSameDay(label: String, reference: Date, calendar: Calendar) -> Bool {
        guard let date = parsedDate(from: label, calendar: calendar) else { return false }
        return calendar.isDate(date, inSameDayAs: reference)
    }

    private func resolveTotalCapacity(
        primary: MemberTopResponse.ServiceInfo,
        services: [MemberTopResponse.ServiceInfo]
    ) -> Double {
        let primaryCapacity = primary.totalCapacity ?? 0
        guard let primaryCoupons = primary.couponData, !primaryCoupons.isEmpty else {
            return primaryCapacity
        }

        let signature = couponSignature(primaryCoupons)
        let matchedCapacities = services.compactMap { service -> Double? in
            guard let coupons = service.couponData, !coupons.isEmpty,
                  couponSignature(coupons) == signature else {
                return nil
            }
            return service.totalCapacity
        }
        let total = matchedCapacities.reduce(0, +)
        return total > 0 ? total : primaryCapacity
    }

    private func resolveCouponMetrics(
        for service: MemberTopResponse.ServiceInfo,
        calendar: Calendar
    ) -> (remaining: Double, carryover: Double) {
        guard let coupons = service.couponData, !coupons.isEmpty else {
            return (service.remainingDataGB ?? 0, 0)
        }

        let now = Date()
        let currentKey = monthKey(from: now, calendar: calendar)
        let nextDate = calendar.date(byAdding: .month, value: 1, to: now) ?? now
        let nextKey = monthKey(from: nextDate, calendar: calendar)

        var remaining = 0.0
        var carryover = 0.0
        var matched = false

        for entry in coupons {
            let value = max(entry.couponValue ?? 0, 0)
            guard let entryMonth = entry.month.flatMap(parseMonthKey) else {
                remaining += value
                matched = true
                continue
            }
            guard entryMonth >= currentKey && entryMonth <= nextKey else { continue }
            remaining += value
            matched = true
            if entryMonth == currentKey {
                carryover += value
            }
        }

        if !matched {
            remaining = service.remainingDataGB ?? 0
            carryover = 0
        }

        return (remaining: max(remaining, 0), carryover: max(carryover, 0))
    }

    private func monthKey(from date: Date, calendar: Calendar) -> Int {
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        return year * 100 + month
    }

    private func parseMonthKey(_ month: String) -> Int? {
        let digits = month.filter { $0.isNumber }
        guard digits.count >= 6, let value = Int(digits.prefix(6)) else { return nil }
        return value
    }

    private func couponSignature(_ coupons: [MemberTopResponse.ServiceInfo.CouponEntry]) -> String {
        let sorted = coupons.sorted { lhs, rhs in
            let lhsSeq = lhs.sequenceNo ?? -1
            let rhsSeq = rhs.sequenceNo ?? -1
            if lhsSeq != rhsSeq {
                return lhsSeq < rhsSeq
            }
            return (lhs.month ?? "") < (rhs.month ?? "")
        }
        return sorted.map { entry in
            let sequence = entry.sequenceNo.map(String.init) ?? "-"
            let month = entry.month ?? "-"
            let value = entry.couponValue.map { String(format: "%.4f", $0) } ?? "-"
            let adjustment = entry.adjustmentCoupon == true ? "1" : "0"
            return "\(sequence):\(month):\(value):\(adjustment)"
        }.joined(separator: "|")
    }

    private func parsedDate(from label: String, calendar: Calendar) -> Date? {
        let regex = try? NSRegularExpression(pattern: "\\d+")
        let nsString = label as NSString
        let matches = regex?.matches(in: label, range: NSRange(location: 0, length: nsString.length)) ?? []
        let segments = matches.compactMap { Int(nsString.substring(with: $0.range)) }

        guard !segments.isEmpty else { return nil }

        var year = calendar.component(.year, from: Date())
        var month: Int?
        var day: Int?

        if segments.count >= 3 {
            if let first = segments.first, first >= 1000 {
                year = first
                month = segments.dropFirst().first
                day = segments.dropFirst(2).first
            } else if let last = segments.last, last >= 1000 {
                year = last
                month = segments.first
                day = segments.dropFirst().first
            }
        } else if segments.count == 2 {
            month = segments[0]
            day = segments[1]
        } else if segments.count == 1 {
            day = segments[0]
        }

        guard let month, let day else { return nil }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return calendar.date(from: components)
    }

    private func resolveMonthlyHighSpeedMB(
        from payload: AggregatePayload,
        year: Int,
        month: Int,
        calendar: Calendar
    ) -> Double {
        payload.monthlyUsage.reduce(0.0) { serviceSum, service in
            serviceSum + service.entries.reduce(0.0) { entrySum, entry in
                guard entry.hasData,
                      let entryDate = parsedYearMonth(from: entry.monthLabel, calendar: calendar),
                      calendar.component(.year, from: entryDate) == year,
                      calendar.component(.month, from: entryDate) == month else {
                    return entrySum
                }
                let roundedGB = max(entry.highSpeedGB ?? 0, 0)
                let correctionGB = roundingCompensationGB(from: entry.highSpeedText)
                return entrySum + (roundedGB + correctionGB) * 1024
            }
        }
    }

    private func roundingCompensationGB(from text: String?) -> Double {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return 0
        }
        let cleaned = text.replacingOccurrences(of: ",", with: "")
        let numberPart = cleaned.prefix { character in
            character.isNumber || character == "."
        }
        let parts = numberPart.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return 0 }
        let decimalDigits = parts[1].count
        guard decimalDigits > 0 else { return 0 }
        let step = pow(10.0, -Double(decimalDigits))
        return step / 2
    }

    private func parsedYearMonth(from label: String, calendar: Calendar) -> Date? {
        let regex = try? NSRegularExpression(pattern: "\\d+")
        let nsString = label as NSString
        let matches = regex?.matches(in: label, range: NSRange(location: 0, length: nsString.length)) ?? []
        let segments = matches.compactMap { Int(nsString.substring(with: $0.range)) }

        guard !segments.isEmpty else { return nil }

        var year = calendar.component(.year, from: Date())
        var month: Int?

        if segments.count >= 2 {
            if let first = segments.first, first >= 1000 {
                year = first
                month = segments.dropFirst().first
            } else if let last = segments.last, last >= 1000 {
                year = last
                month = segments.first
            } else {
                month = segments.first
            }
        } else if segments.count == 1 {
            month = segments.first
        }

        guard let month else { return nil }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        return calendar.date(from: components)
    }
}
