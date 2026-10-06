import Foundation

struct WidgetRefreshService {
    enum LoginSource { case gapiToken, gapiKeychain, gapiManual, mock }
    enum FetchScope { case full, topOnly }

    struct RefreshOutcome {
        let payload: AggregatePayload
        let loginSource: LoginSource
    }

    private let credentialStore = CredentialStore()
    private let gapiClient = MyIIJmioAPIClient()
    private let dailyClient = ThirtyDayUsageClient()
    private let widgetDataStore = WidgetDataStore()
    private let payloadStore = AggregatePayloadStore()
    private let debugStore = DebugResponseStore.shared

    func refreshForWidget(forceGAPIUpdate: Bool = false) async throws -> RefreshOutcome {
        // 同日のGAPI月次・契約・請求は再利用。30日表はここでは取得しない。
        let cached = payloadStore.load()
        let freshHistory = cached.map { UsageDateLabel.calendar.isDateInToday($0.historyFetchedAt) } ?? false
        return try await refresh(fetchScope: freshHistory && !forceGAPIUpdate ? .topOnly : .full, forceGAPIUpdate: forceGAPIUpdate)
    }

    func refresh(
        manualCredentials: Credentials? = nil,
        persistManualCredentials: Bool = true,
        allowSessionReuse: Bool = true,
        allowKeychainFallback: Bool = true,
        fetchScope: FetchScope = .full,
        forceGAPIUpdate: Bool = false
    ) async throws -> RefreshOutcome {
        debugStore.beginCaptureSession()
        defer { debugStore.finalizeCaptureSession() }
        if let mock = mockOutcome(manualCredentials: manualCredentials,
                                  persistManualCredentials: persistManualCredentials,
                                  allowKeychainFallback: allowKeychainFallback) { return mock }
        if !allowSessionReuse { clearSessionArtifacts() }
        let stored = allowKeychainFallback ? try credentialStore.load() : nil
        let credentials = manualCredentials ?? stored
        let cached = payloadStore.load()
        // 初回・回線変更時に不完全なtop-onlyキャッシュを作らない。
        let useTopOnly = fetchScope == .topOnly && cached != nil
        var source: LoginSource = .gapiToken
        let fetched: AggregatePayload

        func fetch(_ credentials: Credentials?) async throws -> AggregatePayload {
            if useTopOnly, let cached {
                let latest: (top: TrafficSummary, dailyUsage: [DailyUsageService])
                if let credentials {
                    latest = try await gapiClient.fetchTop(credentials: credentials, forceUpdate: forceGAPIUpdate)
                } else {
                    latest = try await gapiClient.fetchTopUsingExistingSession(forceUpdate: forceGAPIUpdate)
                }
                if Set(latest.top.serviceInfoList.map(\.id)) == Set(cached.top.serviceInfoList.map(\.id)) {
                    return AggregatePayload(
                        fetchedAt: Date(), top: latest.top, bill: cached.bill,
                        serviceStatus: cached.serviceStatus, monthlyUsage: cached.monthlyUsage,
                        dailyUsage: DailyUsageMerger.merge(history: cached.dailyUsage, current: latest.dailyUsage),
                        billDetails: cached.billDetails, historyFetchedAt: cached.historyFetchedAt
                    )
                }
            }
            let gapi: AggregatePayload
            if let credentials {
                gapi = try await gapiClient.fetchAll(credentials: credentials, forceUpdate: forceGAPIUpdate)
            } else {
                gapi = try await gapiClient.fetchAllUsingExistingSession(forceUpdate: forceGAPIUpdate)
            }
            return gapi
        }

        if allowSessionReuse {
            do {
                fetched = try await fetch(nil)
            } catch {
                guard gapiClient.isAuthenticationError(error) else { throw error }
                gapiClient.clearPersistedSession()
                guard let credentials else { throw WidgetRefreshError.missingCredentials }
                fetched = try await fetch(credentials)
                source = manualCredentials != nil ? .gapiManual : .gapiKeychain
            }
        } else {
            guard let credentials else { throw WidgetRefreshError.missingCredentials }
            fetched = try await fetch(credentials)
            source = manualCredentials != nil ? .gapiManual : .gapiKeychain
        }
        // 通常更新はGAPIのみ。取得済みの30日表は現存する回線分だけ保持する。
        var result = fetched
        let lineIDs = Set(result.top.serviceInfoList.map(\.id))
        result.thirtyDayUsage = payloadStore.load()?.thirtyDayUsage?.filter { lineIDs.contains($0.lineID) }
        try Task.checkCancellation()
        if persistManualCredentials, let manualCredentials { try credentialStore.save(manualCredentials) }
        return finalize(payload: result, source: source)
    }

    /// 利用量タブを開いた時だけ取得する。GAPIの更新日時や認証状態は変更しない。
    func refreshUsageHistory() async throws -> AggregatePayload {
        guard let cached = payloadStore.load() else { throw MyIIJmioAPIError.invalidResponse }
        let credentials = try credentialStore.load()
        if let credentials, MockPayloadProvider.isMockCredentials(credentials) { return cached }
        debugStore.beginCaptureSession()
        defer { debugStore.finalizeCaptureSession() }

        let history: [DailyUsageService]
        do {
            history = try await dailyClient.fetchThirtyDays()
        } catch {
            guard dailyClient.isAuthenticationError(error) else { throw error }
            guard let credentials else { throw WidgetRefreshError.missingCredentials }
            history = try await dailyClient.fetchThirtyDays(credentials: credentials)
        }
        let normalized = try DailyUsageMerger.match(history: history, lines: cached.top.serviceInfoList)
        try Task.checkCancellation()
        // 取得中のWidget更新を巻き戻さず、ログアウト・アカウント/回線変更後には保存しない。
        guard var latest = payloadStore.load(),
              Set(latest.top.serviceInfoList.map(\.id)) == Set(cached.top.serviceInfoList.map(\.id)),
              try credentialStore.load() == credentials else { throw ThirtyDayUsageError.invalidSession }
        latest.thirtyDayUsage = normalized
        payloadStore.save(payload: latest)
        return latest
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
        if let manualCredentials, MockPayloadProvider.isMockCredentials(manualCredentials) {
            guard let detail = MockPayloadProvider.billDetail(for: entry) else { throw MyIIJmioAPIError.invalidResponse }
            return detail
        }
        if let stored = try credentialStore.load(), MockPayloadProvider.isMockCredentials(stored) {
            guard let detail = MockPayloadProvider.billDetail(for: entry) else { throw MyIIJmioAPIError.invalidResponse }
            return detail
        }
        if let detail = payloadStore.load()?.billDetails[entry.id] { return detail }
        do {
            return try await gapiClient.fetchBillDetailUsingExistingSession(entry: entry)
        } catch {
            guard gapiClient.isAuthenticationError(error) else { throw error }
            gapiClient.clearPersistedSession()
        }
        guard let credentials = try manualCredentials ?? credentialStore.load() else {
            throw WidgetRefreshError.missingCredentials
        }
        return try await gapiClient.fetchBillDetail(entry: entry, credentials: credentials)
    }

    func clearSessionArtifacts() {
        gapiClient.clearPersistedSession()
        dailyClient.clearPersistedSession()
        payloadStore.clear()
        widgetDataStore.clear()
    }
}
