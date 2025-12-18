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
              let totalCapacity = primaryServiceInfo.totalCapacity,
              let remaining = primaryServiceInfo.remainingDataGB,
              !payload.dailyUsage.isEmpty else {
            return payload
        }

        // 既に当日行が存在する場合はそのまま
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        if payload.dailyUsage.contains(where: { service in
            service.entries.contains { isSameDay(label: $0.dateLabel, reference: today, calendar: calendar) }
        }) {
            return payload
        }

        // 当月の累計MB (当日を除く) を集計
        let currentMonth = calendar.component(.month, from: today)
        let currentYear = calendar.component(.year, from: today)
        let pastMB = payload.dailyUsage.reduce(0.0) { serviceSum, service in
            serviceSum + service.entries.reduce(0.0) { entrySum, entry in
                guard entry.hasData,
                      let entryDate = parsedDate(from: entry.dateLabel, calendar: calendar),
                      calendar.component(.month, from: entryDate) == currentMonth,
                      calendar.component(.year, from: entryDate) == currentYear,
                      !calendar.isDate(entryDate, inSameDayAs: today) else {
                    return entrySum
                }
                return entrySum + (entry.highSpeedMB ?? 0) + (entry.lowSpeedMB ?? 0)
            }
        }

        // 残量差分から当日利用量を算出 (GB→MBは1000換算)
        let usedTotalMB = max((totalCapacity - remaining) * 1000, 0)
        let todayMB = max(usedTotalMB - pastMB, 0)

        // 当日行をプライマリサービスに追加
        var services = payload.dailyUsage
        guard var primaryDaily = services.first else { return payload }

        var filtered = primaryDaily.entries.filter {
            !isSameDay(label: $0.dateLabel, reference: today, calendar: calendar)
        }

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
}
